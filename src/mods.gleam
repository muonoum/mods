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
import gleam/result
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
    ["launcher", version] -> launcher(version)
    ["list", version, directory] -> list(version:, directory:)
    ["update", version, directory] -> update(version:, directory:)
    _else -> panic
  }
}

fn launcher(version: String) -> Nil {
  let #(launcher_uri, launcher_filename) = fabric.get_launcher(version)
  io.println(launcher_filename <> " " <> uri.to_string(launcher_uri))
}

fn list(version version: String, directory directory: String) -> Nil {
  let mods_directory = filepath.join(directory, "mods")

  let assert [existing_launcher] =
    path.wildcard(directory, "fabric-server-*.jar")

  let #(launcher_uri, launcher_filename) = fabric.get_launcher(version)

  io.println(case existing_launcher == launcher_filename {
    True -> ansi.cyan(existing_launcher)

    False ->
      [
        ansi.grey(existing_launcher),
        ansi.cyan(launcher_filename),
        uri.to_string(launcher_uri),
      ]
      |> string.join(" ")
  })

  use status <- list.each(get_updates(version:, directory: mods_directory))

  io.println(case status {
    NotFound(name) -> ansi.grey(name)
    UpToDate(name) -> ansi.green(name)
    Updated(name, update) ->
      [ansi.grey(name), ansi.green(update.filename), update.uri]
      |> string.join(" ")
  })
}

fn update(version version: String, directory directory: String) -> Nil {
  let assert [existing_launcher] =
    path.wildcard(directory, "fabric-server-*.jar")

  let #(launcher_uri, launcher_filename) = fabric.get_launcher(version)

  io.println(case existing_launcher == launcher_filename {
    True -> ansi.cyan(existing_launcher)

    False -> {
      let assert Ok(request) = request.from_uri(launcher_uri)

      let assert Ok(response) =
        request.set_body(request, option.None)
        |> httpc.send([])

      let assert Ok(Nil) =
        simplifile.write_bits(launcher_filename, response.body)

      let assert Ok(Nil) = simplifile.delete_file(existing_launcher)

      [ansi.grey(existing_launcher), ansi.green(launcher_filename)]
      |> string.join(" ")
    }
  })

  let mods_directory = filepath.join(directory, "mods")
  use status <- list.each(get_updates(version:, directory: mods_directory))

  io.println(case status {
    NotFound(name) -> ansi.grey(name)
    UpToDate(name) -> ansi.green(name)

    Updated(name, update) -> {
      let assert Ok(request) =
        uri.parse(update.uri)
        |> result.try(request.from_uri)

      let assert Ok(response) =
        request.set_body(request, option.None)
        |> httpc.send([])

      let assert Ok(Nil) =
        filepath.join(mods_directory, update.filename)
        |> simplifile.write_bits(response.body)

      let assert Ok(Nil) =
        simplifile.delete_file(filepath.join(mods_directory, name))

      [ansi.grey(name), ansi.green(update.filename)]
      |> string.join(" ")
    }
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
