import argv
import filepath
import gleam/bit_array
import gleam/crypto
import gleam/io
import gleam/list
import gleam/string
import gleam/uri
import mods/fabric
import mods/modrinth
import muon/extra_erlang/path
import simplifile

pub fn main() -> Nil {
  let assert [mode, game_version, source, destination] = argv.load().arguments
  let #(launcher_uri, launcher_filename) = fabric.get_launcher(game_version)

  let hashes = {
    use name <- list.map(path.wildcard(source, "*.jar"))
    let assert Ok(bits) = simplifile.read_bits(filepath.join(source, name))

    crypto.hash(crypto.Sha1, bits)
    |> bit_array.base16_encode
    |> string.lowercase
  }

  let updates = modrinth.get_updates(hashes, game_version)

  io.println({
    output(
      mode:,
      uri: uri.to_string(launcher_uri),
      path: filepath.join(destination, launcher_filename),
    )
  })

  use file <- list.each(updates)

  filepath.join(destination, file.filename)
  |> output(mode, file.url, _)
  |> io.println
}

fn output(mode mode: String, uri uri: String, path path: String) -> String {
  case mode {
    "curl" -> "curl -L " <> uri <> " > " <> path
    "list" -> uri <> "," <> path
    _else -> panic as "mode"
  }
}
