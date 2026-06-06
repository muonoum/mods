import gleam/string

pub const installer_uri = "https://meta.fabricmc.net/v2/versions/installer"

pub const updates_uri = "https://api.modrinth.com/v2/version_files/update"

pub fn loader_uri(game_version: String) -> String {
  "https://meta.fabricmc.net/v2/versions/loader/" <> game_version
}

pub fn launcher_uri(game: String, loader: String, installer: String) -> String {
  let path = string.join([game, loader, installer], "/")
  "https://meta.fabricmc.net/v2/versions/loader/" <> path <> "/server/jar"
}

pub fn launcher_filename(
  game: String,
  loader: String,
  installer: String,
) -> String {
  let game = "-mc." <> game
  let loader = "-loader." <> loader
  let installer = "-launcher." <> installer
  "fabric-server" <> game <> loader <> installer <> ".jar"
}
