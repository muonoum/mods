import gleam/dynamic/decode
import gleam/http/request
import gleam/json
import gleam/option
import gleam/result
import gleam/uri
import mods/config
import muon/extra_erlang/httpc

pub fn get_loader(game_version: String) -> String {
  let assert Ok(uri) =
    config.loader_uri(game_version)
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

pub fn get_installer() -> String {
  let assert Ok(uri) = uri.parse(config.installer_uri)

  let assert Ok(request) =
    request.from_uri(uri)
    |> result.map(request.set_body(_, option.None))

  let assert Ok(response) = httpc.send(request, [])

  let assert Ok(installer) =
    decode.at([0], decode.at(["version"], decode.string))
    |> json.parse_bits(response.body, _)

  installer
}
