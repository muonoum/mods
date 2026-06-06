import gleam/dynamic/decode
import gleam/http/request
import gleam/json
import gleam/option
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import muon/extra_erlang/httpc

const installer_uri = "https://meta.fabricmc.net/v2/versions/installer"

fn loader_uri(game_version: String) -> String {
  "https://meta.fabricmc.net/v2/versions/loader/" <> game_version
}

fn launcher_filename(
  game: String,
  loader: String,
  installer: String,
) -> String {
  let game = "-mc." <> game
  let loader = "-loader." <> loader
  let installer = "-launcher." <> installer
  "fabric-server" <> game <> loader <> installer <> ".jar"
}

fn launcher_uri(game: String, loader: String, installer: String) -> String {
  let path = string.join([game, loader, installer], "/")
  "https://meta.fabricmc.net/v2/versions/loader/" <> path <> "/server/jar"
}

pub fn get_launcher(game_version: String) -> #(Uri, String) {
  let loader_version = get_loader(game_version)
  let installer_version = get_installer()

  let assert Ok(launcher_uri) =
    launcher_uri(game_version, loader_version, installer_version)
    |> uri.parse

  let launcher_filename =
    launcher_filename(game_version, loader_version, installer_version)

  #(launcher_uri, launcher_filename)
}

fn get_loader(game_version: String) -> String {
  let assert Ok(uri) =
    loader_uri(game_version)
    |> uri.parse

  let assert Ok(request) =
    request.from_uri(uri)
    |> result.map(request.set_body(_, option.None))

  let assert Ok(response) = httpc.send(request, [])

  let assert Ok(loader) =
    decode.at([0], decode.at(["loader", "version"], decode.string))
    |> json.parse_bits(response.body, _)

  loader
}

fn get_installer() -> String {
  let assert Ok(uri) = uri.parse(installer_uri)

  let assert Ok(request) =
    request.from_uri(uri)
    |> result.map(request.set_body(_, option.None))

  let assert Ok(response) = httpc.send(request, [])

  let assert Ok(installer) =
    decode.at([0], decode.at(["version"], decode.string))
    |> json.parse_bits(response.body, _)

  installer
}
