import argv
import filepath
import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/dict
import gleam/io
import gleam/list
import gleam/string
import gleam/uri
import mods/fabric
import mods/modrinth
import muon/extra_erlang/path
import simplifile

pub fn main() -> Nil {
  let assert [game_version, source, destination] = argv.load().arguments
  let #(launcher_uri, launcher_filename) = fabric.get_launcher(game_version)

  let files =
    dict.from_list({
      use name <- list.map(path.wildcard(source, "*.jar"))
      let assert Ok(bits) = simplifile.read_bits(filepath.join(source, name))

      let hash =
        crypto.hash(crypto.Sha1, bits)
        |> bit_array.base16_encode
        |> string.lowercase

      #(hash, name)
    })

  let updates = modrinth.get_updates(dict.keys(files), game_version)

  let skipped = {
    use diff, hash, name <- dict.fold(files, [])
    use <- bool.guard(dict.has_key(updates, hash), diff)
    [name, ..diff]
  }

  list.each(skipped, fn(name) { io.println("# " <> name) })

  io.println({
    download(
      uri.to_string(launcher_uri),
      filepath.join(destination, launcher_filename),
    )
  })

  use update <- list.each(list.flatten(dict.values(updates)))

  filepath.join(destination, update.filename)
  |> download(update.uri, _)
  |> io.println
}

fn download(uri: String, path: String) -> String {
  "curl -L " <> uri <> " > " <> path
}
