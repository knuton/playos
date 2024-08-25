(** Type containing version information.
*)
type version_info =
  {(* the latest available version *)
    latest : Semver.t

  (* version of currently booted system *)
  ; booted : Semver.t

  (* version of inactive system *)
  ; inactive : Semver.t
  }
[@@deriving sexp]

(** State of update mechanism *)
type state =
  | GettingVersionInfo
  | ErrorGettingVersionInfo of string
  | UpToDate of version_info
  | Downloading of string
  | ErrorDownloading of string
  | Installing of string
  | ErrorInstalling of string
  | RebootRequired
  | OutOfDateVersionSelected
  | ReinstallRequired
[@@deriving sexp]

val start : connman:Connman.Manager.t -> rauc:Rauc.t -> update_url:string -> state Lwt_react.signal * unit Lwt.t
