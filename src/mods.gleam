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
import gleam/uri.{type Uri}
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
    ["list", version, directory] -> {
      update_launcher(version:, directory:, on_update: dont_update)
      update_mods(version:, directory:, on_update: dont_update)
    }

    ["update", version, directory] -> {
      update_launcher(version:, directory:, on_update: update_file)
      update_mods(version:, directory:, on_update: update_file)
    }

    _else -> panic
  }
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

fn dont_update(_from, _uri, _to) -> Nil {
  Nil
}

fn update_file(from: String, uri: Uri, to: String) -> Nil {
  let assert Ok(request) = request.from_uri(uri)

  let assert Ok(response) =
    request.set_body(request, option.None)
    |> httpc.send([])

  let assert Ok(Nil) = simplifile.write_bits(to, response.body)
  let assert Ok(Nil) = simplifile.delete_file(from)

  Nil
}

fn update_launcher(
  version version: String,
  directory directory: String,
  on_update on_update: fn(String, Uri, String) -> Nil,
) -> Nil {
  let assert [from] = path.wildcard(directory, "fabric-server-*.jar")
  let #(uri, to) = fabric.get_launcher(version)

  io.println(case from == to {
    True -> ansi.cyan(from)

    False -> {
      on_update(from, uri, to)
      let from = filepath.base_name(from)
      let to = filepath.base_name(to)
      ansi.grey(from) <> " " <> ansi.cyan(to) <> " " <> uri.to_string(uri)
    }
  })
}

fn update_mods(
  version version: String,
  directory directory: String,
  on_update on_update: fn(String, Uri, String) -> Nil,
) -> Nil {
  let directory = filepath.join(directory, "mods")
  use status <- list.each(get_updates(version:, directory:))

  io.println(case status {
    NotFound(from) -> ansi.grey(from)
    UpToDate(from) -> ansi.green(from)

    Updated(from, update) -> {
      on_update(from, update.uri, update.filename)
      let from = filepath.base_name(from)
      let to = filepath.base_name(update.filename)
      ansi.green(to) <> " " <> ansi.grey(from)
    }
  })
}
