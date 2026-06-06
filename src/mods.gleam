import argv
import filepath
import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/crypto
import gleam/dict
import gleam/dynamic/decode.{type Decoder}
import gleam/http
import gleam/http/request.{type Request}
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import muon/extra_erlang/httpc
import muon/extra_erlang/path
import simplifile

type Version {
  UpdateResponse(version_type: String, files: List(File))
}

type File {
  File(url: String, filename: String, hash: String)
}

pub fn main() -> Nil {
  let assert [game, source, destination] = argv.load().arguments

  let assert Ok(loader) = get_loader(game)
  let assert Ok(installer) = get_installer()
  let assert Ok(launcher_uri) = launcher_uri(game, loader, installer)

  io.println(download(
    uri.to_string(launcher_uri),
    filepath.join(destination, launcher_filename(game, loader, installer)),
  ))

  let hashes = {
    use name <- list.map(path.wildcard(source, "*.jar"))
    let path = filepath.join(source, name)
    let assert Ok(hash) = get_hash(path)
    hash
  }

  let assert Ok(updates_request) = updates_request(hashes, game)
  let assert Ok(updates_response) = httpc.send(updates_request, [])

  let assert Ok(updates) =
    json.parse_bits(
      updates_response.body,
      decode.dict(decode.string, version_decoder()),
    )

  use version <- list.each(dict.values(updates))
  use file <- list.each(version.files)

  filepath.join(destination, file.filename)
  |> download(file.url, _)
  |> io.println
}

fn launcher_filename(
  game: String,
  loader: String,
  installer: String,
) -> String {
  "fabric-server"
  <> { "-mc." <> game }
  <> { "-loader." <> loader }
  <> { "-launcher." <> installer }
  <> ".jar"
}

fn loader_uri(game_version: String) -> Result(Uri, Nil) {
  uri.parse("https://meta.fabricmc.net/v2/versions/loader/" <> game_version)
}

fn installer_uri() -> Result(Uri, Nil) {
  uri.parse("https://meta.fabricmc.net/v2/versions/installer")
}

fn launcher_uri(
  game: String,
  loader: String,
  installer: String,
) -> Result(Uri, Nil) {
  let path = string.join([game, loader, installer], "/")

  uri.parse(
    "https://meta.fabricmc.net/v2/versions/loader/" <> path <> "/server/jar",
  )
}

fn updates_uri() -> Result(Uri, Nil) {
  uri.parse("https://api.modrinth.com/v2/version_files/update")
}

fn download(url: String, path: String) -> String {
  // "curl -L " <> url <> " > " <> path
  url <> "," <> path
}

fn version_decoder() -> Decoder(Version) {
  use version_type <- decode.field("version_type", decode.string)
  use files <- decode.field("files", decode.list(file_decoder()))
  decode.success(UpdateResponse(version_type:, files:))
}

fn file_decoder() -> Decoder(File) {
  use url <- decode.field("url", decode.string)
  use filename <- decode.field("filename", decode.string)
  use hash <- decode.subfield(["hashes", "sha1"], decode.string)
  decode.success(File(filename:, url:, hash:))
}

fn updates_request(
  hashes: List(String),
  version: String,
) -> Result(Request(Option(BytesTree)), Nil) {
  use uri <- result.try(updates_uri())
  use request <- result.map(request.from_uri(uri))

  let body =
    updates_arguments(hashes, version)
    |> json.to_string_tree
    |> bytes_tree.from_string_tree

  request.set_method(request, http.Post)
  |> request.set_header("content-type", "application/json")
  |> request.set_body(option.Some(body))
}

fn updates_arguments(hashes: List(String), version: String) -> json.Json {
  json.object([
    #("algorithm", json.string("sha1")),
    #("hashes", json.array(hashes, json.string)),
    #("loaders", json.preprocessed_array([json.string("fabric")])),
    #("game_versions", json.preprocessed_array([json.string(version)])),
  ])
}

fn get_hash(path: String) -> Result(String, simplifile.FileError) {
  use bits <- result.map(simplifile.read_bits(path))

  crypto.hash(crypto.Sha1, bits)
  |> bit_array.base16_encode
  |> string.lowercase
}

fn get_loader(game_version: String) -> Result(String, json.DecodeError) {
  let assert Ok(uri) = loader_uri(game_version)

  let assert Ok(request) =
    request.from_uri(uri)
    |> result.map(request.set_body(_, option.None))

  let assert Ok(response) = httpc.send(request, [])

  json.parse_bits(
    response.body,
    decode.at([0], decode.at(["loader", "version"], decode.string)),
  )
}

fn get_installer() -> Result(String, json.DecodeError) {
  let assert Ok(uri) = installer_uri()

  let assert Ok(request) =
    request.from_uri(uri)
    |> result.map(request.set_body(_, option.None))

  let assert Ok(response) = httpc.send(request, [])

  json.parse_bits(
    response.body,
    decode.at([0], decode.at(["version"], decode.string)),
  )
}
