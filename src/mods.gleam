import argv
import filepath
import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/dict
import gleam/http/request
import gleam/io
import gleam/list
import gleam/option
import gleam/pair
import gleam/string
import gleam/uri
import gleam_community/ansi
import mods/fabric
import mods/modrinth
import muon/extra_erlang/httpc
import muon/extra_erlang/path
import simplifile

type Status {
  NotFound(String)
  UpToDate(String)
  Updated(String, modrinth.File)
}

pub fn main() -> Nil {
  case argv.load().arguments {
    ["list", version, directory] -> list(version:, directory:)
    ["update", version, directory] -> update(version:, directory:)
    _else -> panic
  }
}

fn list(version version: String, directory directory: String) -> Nil {
  update_launcher(version:, directory:, on_update: fn(uri, from, to) {
    ansi.grey(from) <> " " <> ansi.cyan(to) <> " " <> uri.to_string(uri)
  })

  update_mods(version:, directory:, on_update: fn(uri, from, to) {
    ansi.grey(from) <> " " <> ansi.green(to) <> " " <> uri
  })
}

fn update(version version: String, directory directory: String) -> Nil {
  update_launcher(version:, directory:, on_update: fn(uri, from, to) {
    update_file(uri, from, to)
    ansi.grey(from) <> " " <> ansi.green(from)
  })

  update_mods(version:, directory:, on_update: fn(uri, from, to) {
    let assert Ok(uri) = uri.parse(uri)
    update_file(uri, from, to)
    ansi.grey(from) <> " " <> ansi.green(to)
  })
}

fn get_updates(
  version version: String,
  directory directory: String,
) -> List(Status) {
  let existing =
    dict.from_list({
      use name <- list.map(path.wildcard(directory, "*.jar"))
      let path = filepath.join(directory, name)
      let assert Ok(bits) = simplifile.read_bits(path)

      crypto.hash(crypto.Sha1, bits)
      |> bit_array.base16_encode
      |> string.lowercase
      |> pair.new(name)
    })

  let updated =
    dict.keys(existing)
    |> modrinth.get_updates(version)

  let updates = {
    use #(hash, files) <- list.flat_map(dict.to_list(updated))
    let assert Ok(original) = dict.get(existing, hash)
    use file <- list.map(files)

    case hash == file.hash {
      True -> UpToDate(original)
      False -> Updated(original, file)
    }
  }

  use updates, hash, name <- dict.fold(existing, updates)
  use <- bool.guard(dict.has_key(updated, hash), updates)
  [NotFound(name), ..updates]
}

fn update_file(uri: uri.Uri, from: String, to: String) -> Nil {
  let assert Ok(request) = request.from_uri(uri)
  let request = request.set_body(request, option.None)
  let assert Ok(response) = httpc.send(request, [])
  let assert Ok(Nil) = simplifile.write_bits(to, response.body)
  let assert Ok(Nil) = simplifile.delete_file(from)
  Nil
}

fn update_launcher(
  version version: String,
  directory directory: String,
  on_update on_update: fn(uri.Uri, String, String) -> String,
) -> Nil {
  let assert [from] = path.wildcard(directory, "fabric-server-*.jar")
  let #(uri, to) = fabric.get_launcher(version)

  io.println(case from == to {
    True -> ansi.cyan(from)
    False -> on_update(uri, from, to)
  })
}

fn update_mods(
  version version: String,
  directory directory: String,
  on_update on_update: fn(String, String, String) -> String,
) -> Nil {
  let mods_directory = filepath.join(directory, "mods")
  use status <- list.each(get_updates(version:, directory: mods_directory))

  io.println(case status {
    NotFound(from) -> ansi.grey(from)
    UpToDate(from) -> ansi.green(from)

    Updated(from, update) ->
      filepath.join(mods_directory, update.filename)
      |> on_update(update.uri, from, _)
  })
}
