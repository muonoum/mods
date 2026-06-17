import argv
import filepath
import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/dict
import gleam/io
import gleam/list
import gleam/pair
import gleam/string
import gleam/uri
import gleam_community/ansi
import mods/fabric
import mods/modrinth
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
  use status <- list.each(get_updates(version:, directory:))

  io.println(case status {
    NotFound(name) -> ansi.gray(name)
    UpToDate(name) -> ansi.green(name)
    Updated(name, update) ->
      [ansi.grey(name), ansi.green(update.filename), update.uri]
      |> string.join(" ")
  })
}

fn update(version version: String, directory directory: String) -> Nil {
  use status <- list.each(get_updates(version:, directory:))

  io.println(case status {
    NotFound(name) -> ansi.gray(name)
    UpToDate(name) -> ansi.green(name)

    Updated(name, update) -> {
      // TODO: Update
      [ansi.grey(name), ansi.green(update.filename), update.uri]
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
      let assert Ok(bits) = simplifile.read_bits(filepath.join(directory, name))

      crypto.hash(crypto.Sha1, bits)
      |> bit_array.base16_encode
      |> string.lowercase
      |> pair.new(name)
    })

  let updated =
    dict.keys(existing)
    |> modrinth.get_updates(version)

  let updates = {
    use #(hash, updates) <- list.flat_map(dict.to_list(updated))
    let assert Ok(original) = dict.get(existing, hash)
    use file <- list.map(updates)

    case hash == file.hash {
      True -> UpToDate(original)
      False -> Updated(original, file)
    }
  }

  use updates, hash, name <- dict.fold(existing, updates)
  use <- bool.guard(dict.has_key(updated, hash), updates)
  [NotFound(name), ..updates]
}
