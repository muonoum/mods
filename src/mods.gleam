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
  let assert [mode, game_version, source, destination] = argv.load().arguments
  let loader_version = get_loader(game_version)
  let installer_version = get_installer()

  let assert Ok(launcher_uri) =
    launcher_uri(game_version, loader_version, installer_version)

  let launcher =
    launcher_filename(game_version, loader_version, installer_version)

  let hashes = {
    use name <- list.map(path.wildcard(source, "*.jar"))
    get_hash(filepath.join(source, name))
  }

  let updates = get_updates(hashes, game_version)

  io.println({
    output(
      mode:,
      uri: uri.to_string(launcher_uri),
      path: filepath.join(destination, launcher),
    )
  })

  use file <- list.each(updates)

  filepath.join(destination, file.filename)
  |> output(mode, file.url, _)
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

fn updates_uri() -> String {
  "https://api.modrinth.com/v2/version_files/update"
}

fn output(mode mode: String, uri uri: String, path path: String) -> String {
  case mode {
    "curl" -> "curl -L " <> uri <> " > " <> path
    "list" -> uri <> "," <> path
    _else -> panic as "mode"
  }
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
  use uri <- result.try(uri.parse(updates_uri()))

  use request <- result.map(request.from_uri(uri))

  let config =
    json.object([
      #("algorithm", json.string("sha1")),
      #("hashes", json.array(hashes, json.string)),
      #("loaders", json.preprocessed_array([json.string("fabric")])),
      #("game_versions", json.preprocessed_array([json.string(version)])),
    ])

  let body =
    json.to_string_tree(config)
    |> bytes_tree.from_string_tree

  request.set_method(request, http.Post)
  |> request.set_header("content-type", "application/json")
  |> request.set_body(option.Some(body))
}

fn get_hash(path: String) -> String {
  let assert Ok(bits) = simplifile.read_bits(path)

  crypto.hash(crypto.Sha1, bits)
  |> bit_array.base16_encode
  |> string.lowercase
}

fn get_loader(game_version: String) -> String {
  let assert Ok(uri) = loader_uri(game_version)

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
  let assert Ok(uri) = installer_uri()

  let assert Ok(request) =
    request.from_uri(uri)
    |> result.map(request.set_body(_, option.None))

  let assert Ok(response) = httpc.send(request, [])

  let assert Ok(installer) =
    decode.at([0], decode.at(["version"], decode.string))
    |> json.parse_bits(response.body, _)

  installer
}

fn get_updates(hashes: List(String), game_version: String) -> List(File) {
  let assert Ok(request) = updates_request(hashes, game_version)
  let assert Ok(response) = httpc.send(request, [])

  let assert Ok(updates) =
    decode.dict(decode.string, version_decoder())
    |> json.parse_bits(response.body, _)

  use version <- list.flat_map(dict.values(updates))
  version.files
}
