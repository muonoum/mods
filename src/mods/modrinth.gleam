import gleam/bytes_tree
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/http
import gleam/http/request
import gleam/json
import gleam/option
import gleam/result
import gleam/uri.{type Uri}
import muomono/extra_erlang/httpc

const updates_uri = "https://api.modrinth.com/v2/version_files/update"

pub type Version {
  Version(kind: String, files: List(File))
}

pub type File {
  File(uri: Uri, filename: String, hash: String)
}

pub fn get_updates(
  hashes: List(String),
  game_version: String,
) -> Dict(String, Version) {
  let request = {
    let assert Ok(request) =
      uri.parse(updates_uri)
      |> result.try(request.from_uri)

    let config =
      json.object([
        #("algorithm", json.string("sha1")),
        #("hashes", json.array(hashes, json.string)),
        #("loaders", json.preprocessed_array([json.string("fabric")])),
        #("game_versions", json.preprocessed_array([json.string(game_version)])),
      ])

    request.set_method(request, http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(option.Some(
      json.to_string_tree(config)
      |> bytes_tree.from_string_tree,
    ))
  }

  let assert Ok(response) = httpc.send(request, [])

  let assert Ok(updates) =
    decode.dict(decode.string, version_decoder())
    |> json.parse_bits(response.body, _)

  use _hash, version <- dict.map_values(updates)
  version
}

fn version_decoder() -> Decoder(Version) {
  use _project_id <- decode.field("project_id", decode.string)
  use _dependencies <- decode.field("dependencies", decode.dynamic)
  use kind <- decode.field("version_type", decode.string)
  use files <- decode.field("files", decode.list(file_decoder()))
  decode.success(Version(kind:, files:))
}

fn file_decoder() -> Decoder(File) {
  use uri <- decode.field("url", uri_decoder())
  use filename <- decode.field("filename", decode.string)
  use hash <- decode.subfield(["hashes", "sha1"], decode.string)
  decode.success(File(filename:, uri:, hash:))
}

fn uri_decoder() -> Decoder(Uri) {
  use string <- decode.then(decode.string)

  case uri.parse(string) {
    Error(Nil) -> decode.failure(uri.empty, "Uri")
    Ok(uri) -> decode.success(uri)
  }
}
