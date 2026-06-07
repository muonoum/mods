import gleam/dynamic/decode.{type Decoder}
import gleam/http/request
import gleam/json
import gleam/option
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import muon/extra_erlang/httpc

pub fn get_launcher(game_version: String) -> #(Uri, String) {
  let loader_version = get_loader(game_version)
  let installer_version = get_installer()

  let assert Ok(uri) =
    launcher_uri(game_version, loader_version, installer_version)
    |> uri.parse

  let filename =
    launcher_filename(game_version, loader_version, installer_version)

  #(uri, filename)
}

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

fn get_loader(game_version: String) -> String {
  decode.at([0], decode.at(["loader", "version"], decode.string))
  |> get(loader_uri(game_version), _)
}

fn get_installer() -> String {
  decode.at([0], decode.at(["version"], decode.string))
  |> get(installer_uri, _)
}

fn get(uri: String, decoder: Decoder(v)) -> v {
  let assert Ok(request) =
    uri.parse(uri)
    |> result.try(request.from_uri)
    |> result.map(request.set_body(_, option.None))

  let assert Ok(response) = httpc.send(request, [])
  let assert Ok(result) = json.parse_bits(response.body, decoder)
  result
}
