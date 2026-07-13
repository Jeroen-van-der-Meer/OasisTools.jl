# How OasisTools.jl Works

## Reading an OASIS file

The entry point for reading is [`oasisread`](@ref), which returns an [`Oasis`](@ref) object. The pipeline works as follows:

1. **Memory-mapping.** The file is memory-mapped via `Mmap.mmap`, producing a `Vector{UInt8}` backed by the OS page cache. The file's contents are not read into heap memory; instead, the OS pages them in on demand as the parser accesses different byte ranges.

2. **Sequential record parsing.** A `FileParserState` walks through the memory-mapped buffer one record at a time. It reads a record-type byte and dispatches to the corresponding handler function. File-level records (CELLNAME, LAYERNAME, PROPNAME, etc.) populate the parser state's reference dictionaries and layer list. Since records are variable-length, the parser must visit every record in sequence; it cannot skip ahead without reading each record's header and payload size.

3. **Cell collection.** When the parser encounters a CELL record, it does *not* decode the cell's geometry. Instead, a `LazyCellParserState` takes over and *skips* through the cell's body record by record, advancing the byte position without interpreting the payload. The parser records the cell's name (or numeric reference) and the byte range that the cell body spans. This produces a `PreprocessedCell` — a name and a view into the memory-mapped buffer.

4. **Post-processing.** After reaching the END record, `process_cells` converts each `PreprocessedCell` into a [`LazyCell`](@ref) by resolving any numeric name references and attaching the file-level reference dictionaries that are needed to later decode the cell's contents.

5. **Eager vs. lazy.** In the default eager mode (`lazy=false`), every `LazyCell` is then further parsed into a [`Cell`](@ref) object with fully materialized shapes and placements. In lazy mode, the `LazyCell` objects are kept as-is — see [Lazy loading](@ref) below.

### Compressed blocks

If the parser encounters a CBLOCK record at any point, it reads the compressed payload, decompresses it with DEFLATE into a temporary buffer, and recursively parses the contained records using a fresh parser state. The decompressed records are handled identically to uncompressed ones; CBLOCKs are transparent to the rest of the parsing logic.

### Modal variables

The parser maintains a set of modal variables that track the most recently seen values for fields such as layer number, datatype, coordinates, and geometry dimensions. When a record omits a field, the parser substitutes the corresponding modal value. This mirrors the OASIS specification's stateful design.

## Lazy loading

Lazy loading is the key feature that distinguishes OasisTools.jl from other OASIS readers.

OASIS files in semiconductor workflows can range from hundreds of megabytes to many gigabytes. A chip-level layout may contain thousands of cells, but a typical analysis task — inspecting a particular standard cell, checking the hierarchy, extracting a sub-block — only needs a handful of them. Fully parsing every cell on load wastes both time and memory.

### How it works

When you call `oasisread(filename; lazy=true)`, the file is memory-mapped and the parser walks through every record to identify cell boundaries (as described above), but the geometry within each cell is not decoded. Each cell is stored as a [`LazyCell`](@ref), which holds:

- A **view** (`SubArray`) into the memory-mapped file buffer, pointing to the raw bytes of the CELL record body. No bytes are copied.
- The file-level **name reference dictionaries** (cell names and text strings), so the `LazyCell` is self-contained and can be decoded independently at any later point.
- The cell **name**, **unit**, and **root status**.

Because no geometry is decoded and no cell data is copied, opening a file in lazy mode is fast and uses minimal memory beyond the memory-mapped region itself.

### Loading cells on demand

To access the shapes and placements of a lazy-loaded cell, use [`load_cell!`](@ref):

```julia
oas = oasisread("large_chip.oas"; lazy=true)
load_cell!(oas, :StandardCell_NAND2)
shapes(oas[:StandardCell_NAND2])
```

[`load_cell!`](@ref) parses the `LazyCell`'s byte range into shapes and placements, constructs a [`Cell`](@ref) object, and replaces the `LazyCell` in the `Oasis` object. You can also use the non-mutating [`load_cell`](@ref) to get a `Cell` without modifying the `Oasis` object.

To load all cells at once (equivalent to eager mode), use [`load_all_cells!`](@ref).

### Root cell detection

Root cells (cells that are not placed inside any other cell) are detected differently depending on the loading mode:

- Eager mode examines the fully parsed placement data: any cell that is not referenced by a PLACEMENT record in another cell is marked as a root. This is reliable because all placements are known.

- Lazy mode cannot use placement data (since cell contents are not parsed), so it falls back to reading `S_TOP_CELL` file properties. As described in [The OASIS File Format](@ref), `S_TOP_CELL` is an *optional* standard property; there is no guarantee that a given OASIS file includes it. If the property is absent, lazy mode will not identify any root cells.

## Writing an OASIS file

OasisTools.jl contains limited writing functionality. The entry point for writing is [`oasiswrite`](@ref). The pipeline:

1. **Buffered output.** A `WriterState` is created with a large output buffer (16 MB by default). Records are serialized into the buffer and flushed to disk in batches, minimizing the number of write system calls.

2. **Header and metadata.** The magic bytes and START record are written first, followed by file-level properties that declare root cells (`S_TOP_CELL`). Cell name references, property names, and layer names are written inside a CBLOCK for compression.

3. **Cell writing.** Each cell is written in turn:
   - **[`Cell`](@ref) objects** are serialized from their in-memory shapes and placements.
   - **[`LazyCell`](@ref) objects** are handled via *copywriting*: the raw bytes are parsed record by record and re-serialized to the output, allowing numeric cell name references to be remapped without fully decoding the cell's geometry. This enables round-tripping files through lazy loading without materializing every cell.

4. **Footer.** The END record closes the file.

### Compressed block writing

The `write_cblock` function captures output by creating a temporary `WriterState` backed by an in-memory `IOBuffer`. Records are written to this temporary state as usual. Once done, the accumulated bytes are compressed with DEFLATE and written as a CBLOCK record to the main output.
