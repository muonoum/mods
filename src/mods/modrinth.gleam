import gleam/bytes_tree
import gleam/dict
import gleam/dynamic/decode.{type Decoder}
import gleam/http
import gleam/http/request
import gleam/json
import gleam/list
import gleam/option
import gleam/uri
import muon/extra_erlang/httpc

const updates_uri = "https://api.modrinth.com/v2/version_files/update"

type Version {
  UpdateResponse(version_type: String, files: List(File))
}

pub type File {
  File(uri: String, filename: String, hash: String)
}

pub fn get_updates(hashes: List(String), game_version: String) -> List(File) {
  let assert Ok(uri) = uri.parse(updates_uri)
  let assert Ok(request) = request.from_uri(uri)

  let config =
    json.object([
      #("algorithm", json.string("sha1")),
      #("hashes", json.array(hashes, json.string)),
      #("loaders", json.preprocessed_array([json.string("fabric")])),
      #("game_versions", json.preprocessed_array([json.string(game_version)])),
    ])

  let request =
    request.set_method(request, http.Post)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(option.Some(
      json.to_string_tree(config)
      |> bytes_tree.from_string_tree,
    ))

  let assert Ok(response) = httpc.send(request, [])

  let assert Ok(updates) =
    decode.dict(decode.string, version_decoder())
    |> json.parse_bits(response.body, _)

  use version <- list.flat_map(dict.values(updates))
  version.files
}

fn version_decoder() -> Decoder(Version) {
  use version_type <- decode.field("version_type", decode.string)
  use files <- decode.field("files", decode.list(file_decoder()))
  decode.success(UpdateResponse(version_type:, files:))
}

fn file_decoder() -> Decoder(File) {
  use uri <- decode.field("url", decode.string)
  use filename <- decode.field("filename", decode.string)
  use hash <- decode.subfield(["hashes", "sha1"], decode.string)
  decode.success(File(filename:, uri:, hash:))
}
