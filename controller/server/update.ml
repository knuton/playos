open Lwt
open Sexplib.Conv

let log_src = Logs.Src.create "update"

let bundle_name =
  "@PLAYOS_BUNDLE_NAME@"

(* Version handling *)


(** Type containing version information *)
type version_info =
  {(* the latest available version *)
    latest : (Semver.t [@sexp.opaque])

  (* version of currently booted system *)
  ; booted : (Semver.t [@sexp.opaque])

  (* version of inactive system *)
  ; inactive : (Semver.t [@sexp.opaque])
  }
[@@deriving sexp]


(** Helper to parse semver from string or fail *)
let semver_of_string string =
  let trimmed_string = String.trim string
  in
  match Semver.of_string trimmed_string with
  | None ->
    failwith
      (Format.sprintf "could not parse version (version string: %s)" string)
  | Some version ->
    version

(** Get latest version available at [url] *)
let get_latest_version ~proxy url =
  match%lwt Curl.request ?proxy (Uri.of_string (url ^ "latest")) with
  | RequestSuccess (_, body) ->
      return (semver_of_string body)
  | RequestFailure error ->
      Lwt.fail_with (Printf.sprintf "could not get latest version (%s)" (Curl.pretty_print_error error))

(** Get version information *)
let get_version_info ~proxy url rauc =
  Lwt_result.catch
    (fun () ->
      let%lwt latest = get_latest_version ~proxy url in
      let%lwt rauc_status = Rauc.get_status rauc in

      let system_a_version = rauc_status.a.version |> semver_of_string in
      let system_b_version = rauc_status.b.version |> semver_of_string in

      match%lwt Rauc.get_booted_slot rauc with
      | SystemA ->
        { latest = latest
        ; booted = system_a_version
        ; inactive = system_b_version
        }
        |> return
      | SystemB ->
        { latest = latest
        ; booted = system_b_version
        ; inactive = system_a_version
        }
        |> return
    )

let bundle_file_name version =
  Format.sprintf "%s-%s.raucb" bundle_name version

let latest_download_url ~update_url version_string =
  Format.sprintf "%s%s/%s" update_url version_string (bundle_file_name version_string)

(** download RAUC bundle *)
let download ?proxy ~update_url version_string =
  let bundle_path = Format.sprintf "/tmp/%s" (bundle_file_name version_string) in
  let url = Uri.of_string (latest_download_url ~update_url version_string) in
  let options =
    [ "--continue-at"; "-" (* resume download *)
    ; "--limit-rate"; "10M"
    ; "--output"; bundle_path
    ]
  in
  match%lwt Curl.request ?proxy ~options url with
  | RequestSuccess _ ->
      return bundle_path
  | RequestFailure error ->
      Lwt.fail_with (Printf.sprintf "could not download RAUC bundle (%s)" (Curl.pretty_print_error error))

(* Update mechanism process *)

type state =
  | GettingVersionInfo
  | ErrorGettingVersionInfo of string
  | UpToDate of version_info
  | Downloading of string
  | ErrorDownloading of string
  | Installing of string
  | ErrorInstalling of string
  (* inactive system has been updated and reboot is required to boot into updated system *)
  | RebootRequired
  (* inactive system is up to date, but current system was selected for boot *)
  | OutOfDateVersionSelected
  (* there are no known-good systems and a reinstall is recommended *)
  | ReinstallRequired
[@@deriving sexp]

let evaluate_version_info current_primary booted_slot version_info =
  (* Compare latest available version to version booted. *)
  let booted_version_compare = Semver.compare version_info.latest version_info.booted in
  let booted_up_to_date = booted_version_compare = 0 in

  (* Compare latest available version to version on inactive system partition. *)
  let inactive_version_compare = Semver.compare version_info.latest version_info.inactive in
  let inactive_up_to_date = inactive_version_compare = 0 in
  let inactive_update_available = inactive_version_compare > 0 in

  if booted_up_to_date || inactive_up_to_date then
    match current_primary with
    | Some primary_slot ->
      if booted_up_to_date then
        (* Don't care if inactive can be updated. I.e. Only update the inactive partition once the booted partition is outdated. This results in always two versions being available on the machine. *)
        UpToDate version_info |> return
      else
        if booted_slot = primary_slot then
          (* Inactive is up to date while booted is out of date, but booted was specifically selected for boot *)
          OutOfDateVersionSelected |> return
        else
          (* If booted is not up to date but inactive is both up to date and primary, we should reboot into the primary *)
          RebootRequired |> return
    | None ->
      (* All systems bad; suggest reinstallation *)
      ReinstallRequired |> return

  else if inactive_update_available then
    (* Booted system is not up to date and there is an update available for inactive system. *)
    Downloading (Semver.to_string version_info.latest) |> return

  else
    let msg =
      ("nonsensical version information: "
       ^ (version_info
          |> sexp_of_version_info
          |> Sexplib.Sexp.to_string_hum))
    in
    let%lwt () = Logs_lwt.warn ~src:log_src (fun m -> m "%s" msg) in
    ErrorGettingVersionInfo msg |> return


(** Finite state machine handling updates *)
let rec run ~connman ~update_url ~rauc ~set_state =
  (* Helper to update state in signal and advance state machine *)
  let set state =
    set_state state; run ~connman ~update_url ~rauc ~set_state state
  in
  let get_proxy_uri manager = 
      Connman.Manager.get_default_proxy manager >|= Option.map (Connman.Service.Proxy.to_uri ~include_userinfo:true)
  in
  function
  | GettingVersionInfo ->
    (* get version information and decide what to do *)
    let%lwt proxy = get_proxy_uri connman in
    let%lwt current_primary = Rauc.get_primary rauc in
    let%lwt booted_slot = Rauc.get_booted_slot rauc in
    begin
      match%lwt get_version_info ~proxy update_url rauc with
      | Ok version_info ->
        let%lwt next_state = evaluate_version_info current_primary booted_slot version_info in
        set next_state

      | Error exn ->
        ErrorGettingVersionInfo (Printexc.to_string exn)
        |> set
    end

  | ErrorGettingVersionInfo msg ->
    (* handle error while getting version information *)
    let%lwt () =
      Logs_lwt.err ~src:log_src
        (fun m -> m "failed to get version information: %s" msg)
    in
    (* wait for 30 seconds and retry *)
    let%lwt () = Lwt_unix.sleep 30.0 in
    set GettingVersionInfo

  | Downloading version_string ->
    (* download latest version *)
    let%lwt proxy = get_proxy_uri connman in
    (match%lwt Lwt_result.catch (fun () -> download ?proxy ~update_url version_string) with
     | Ok bundle_path ->
       Installing bundle_path
       |> set
     | Error exn ->
       ErrorDownloading (Printexc.to_string exn)
       |> set
    )

  | ErrorDownloading msg ->
    (* handle error while downloading bundle *)
    let%lwt () =
      Logs_lwt.err ~src:log_src
        (fun m -> m "failed to download RAUC bundle: %s" msg)
    in
    (* Wait for 30 seconds and retry *)
    let%lwt () = Lwt_unix.sleep 30.0 in
    set GettingVersionInfo

  | Installing bundle_path ->
    (* install bundle via RAUC *)
    (match%lwt Lwt_result.catch (fun () -> Rauc.install rauc bundle_path) with
     | Ok () ->
       let%lwt () =
         Logs_lwt.info (fun m -> m "succesfully installed update (%s)" bundle_path)
       in
       RebootRequired
       |> set
     | Error exn ->
       let () = try Sys.remove bundle_path with
         | _ -> ()
       in
       ErrorInstalling (Printexc.to_string exn)
       |> set
    )

  | ErrorInstalling msg ->
    (* handle installation error *)
    let%lwt () =
      Logs_lwt.err ~src:log_src
        (fun m -> m "failed to install RAUC bundle: %s" msg)
    in
    (* Wait for 30 seconds and retry *)
    let%lwt () = Lwt_unix.sleep 30.0 in
    set GettingVersionInfo

  | UpToDate _
  | RebootRequired
  | OutOfDateVersionSelected
  | ReinstallRequired ->
    (* wait for an hour and recheck for new updates *)
    let%lwt () = Lwt_unix.sleep (1. *. 60. *. 60.) in
    set GettingVersionInfo


let start ~connman ~(rauc:Rauc.t) ~(update_url:string) =
  let state_s, set_state = Lwt_react.S.create GettingVersionInfo in
  let () = Logs.info ~src:log_src (fun m -> m "update URL: %s" update_url) in
  state_s, run ~connman ~update_url ~rauc ~set_state GettingVersionInfo
