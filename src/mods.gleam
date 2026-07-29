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
import muomono/extra/function.{return}
import muomono/extra_erlang/httpc
import muomono/extra_erlang/path
import simplifile

type Status {
  NotFound(String)
  UpToDate(name: String, kind: String)
  Pending(from: String, to: String, kind: String)
  Updated(from: String, uri: Uri, to: String)
}

pub fn main() -> Nil {
  case argv.load().arguments {
    ["list", version, directory] ->
      update(version:, directory:, on_update: dont_update)

    ["update", version, directory] ->
      update(version:, directory:, on_update: update_file)

    _else -> panic
  }
}

fn update(
  version version: String,
  directory directory: String,
  on_update on_update: fn(String, Uri, String) -> Nil,
) -> Nil {
  update_launcher(version:, directory:, on_update:)
  update_mods(version:, directory:, on_update:)
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

  use #(hash, from) <- list.map(dict.to_list(existing))

  case dict.get(updated, hash) {
    Error(Nil) -> NotFound(from)

    Ok(version) -> {
      let assert [file] = version.files

      use <- bool.guard(
        hash == file.hash,
        UpToDate(name: from, kind: version.kind),
      )

      case version.kind {
        "release" -> Updated(from:, uri: file.uri, to: file.filename)
        kind -> Pending(from:, to: file.filename, kind:)
      }
    }
  }
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
  let join = filepath.join(directory, _)
  let #(uri, to) = fabric.get_launcher(version)
  use <- return(io.println)
  use <- return(string.join(_, " "))

  case from == to {
    True -> [ansi.cyan(from)]

    False -> {
      on_update(join(from), uri, join(to))
      let from = filepath.base_name(from)
      let to = filepath.base_name(to)
      [ansi.grey(from), ansi.cyan(to)]
    }
  }
}

fn update_mods(
  version version: String,
  directory directory: String,
  on_update on_update: fn(String, Uri, String) -> Nil,
) -> Nil {
  let directory = filepath.join(directory, "mods")
  let join = filepath.join(directory, _)
  use status <- list.each(get_updates(version:, directory:))
  use <- return(io.println)
  use <- return(string.join(_, " "))

  case status {
    NotFound(name) -> [ansi.grey(name)]
    UpToDate(name:, kind: "release") -> [ansi.green(name)]
    UpToDate(name:, kind:) -> [ansi.green(name), ansi.yellow(kind)]

    Pending(from:, to:, kind:) -> [
      ansi.green(from),
      ansi.gray(to),
      ansi.yellow(kind),
    ]

    Updated(from:, uri:, to:) -> {
      on_update(join(from), uri, join(to))
      [ansi.grey(from), ansi.green(to)]
    }
  }
}
