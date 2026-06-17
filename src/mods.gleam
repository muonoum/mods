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

pub fn main() -> Nil {
  case argv.load().arguments {
    ["launcher", game_version] -> launcher(game_version)
    ["updates", game_version, source] -> updates(game_version:, source:)
    _else -> panic
  }
}

fn launcher(game_version: String) -> Nil {
  let #(launcher_uri, launcher_filename) = fabric.get_launcher(game_version)
  io.println(launcher_filename <> " " <> uri.to_string(launcher_uri))
}

fn updates(game_version game_version: String, source source: String) -> Nil {
  let files =
    dict.from_list({
      use name <- list.map(path.wildcard(source, "*.jar"))
      let assert Ok(bits) = simplifile.read_bits(filepath.join(source, name))

      crypto.hash(crypto.Sha1, bits)
      |> bit_array.base16_encode
      |> string.lowercase
      |> pair.new(name)
    })

  let updates = modrinth.get_updates(dict.keys(files), game_version)

  let not_found = {
    use diff, hash, name <- dict.fold(files, [])
    use <- bool.guard(dict.has_key(updates, hash), diff)
    [name, ..diff]
  }

  list.map(not_found, ansi.gray)
  |> list.each(io.println)

  use #(hash, updates) <- list.each(dict.to_list(updates))
  let assert Ok(original) = dict.get(files, hash)
  use update <- list.each(updates)

  use <- bool.lazy_guard(hash == update.hash, fn() {
    io.println(ansi.green(original))
  })

  [ansi.grey(original), ansi.green(update.filename), update.uri]
  |> string.join(" ")
  |> io.println
}
