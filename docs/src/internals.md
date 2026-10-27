# How OasisTools.jl Works

## Reading an OASIS file

The entry point for reading is [`oasisread`](@ref), which returns an [`Oasis`](@ref) object. The pipeline works as follows:

1. **Memory-mapping.** The file is memory-mapped via `Mmap.mmap`, producing a `Vector{UInt8}` backed by the OS page cache. The file's contents are not read into heap memory; instead, the OS pages them in on demand as the parser accesses different byte ranges.

2. **Sequential record parsing.** A `FileParserState` walks through the memory-mapped buffer one record at a time. It reads a record-type byte and dispatches to the corresponding handler function. File-level records (CELLNAME, LAYERNAME, PROPNAME, etc.) populate the parser state's reference dictionaries and layer list. Since records are variable-length, the parser must visit every record in sequence; it cannot skip ahead without reading each record's header and payload size.

3. **Cell collection.** When the parser encounters a CELL record, it does *not* decode the cell's geometry. Instead, a `SkipParserState` takes over and *skips* through the cell's body record by record, advancing the byte position without interpreting the payload. Compressed blocks inside the cell are skipped without being decompressed. The parser records the cell's name (or numeric reference) and the byte range that the cell body spans. This produces a `PreprocessedCell` — a name and a view into the memory-mapped buffer.

4. **Post-processing.** After reaching the END record, `process_cells` converts each `PreprocessedCell` into a [`Cell`](@ref) that isn't loaded, by resolving any numeric name references. Its [`CellSource`](@ref OasisTools.CellSource) holds the byte range along with the file-level reference dictionaries that are needed to later decode the cell's contents.

5. **Eager vs. lazy.** In the default eager mode (`lazy=false`), every cell is then loaded: its shapes and placements are decoded into memory. In lazy mode, the cells are left as they are — see [Lazy loading](@ref) below.

### Compressed blocks

If the parser encounters a CBLOCK record at any point, it reads the compressed payload, decompresses it with DEFLATE into a temporary buffer, and recursively parses the contained records using a fresh parser state. The decompressed records are handled identically to uncompressed ones; CBLOCKs are transparent to the rest of the parsing logic.

### Modal variables

The parser maintains a set of modal variables that track the most recently seen values for fields such as layer number, datatype, coordinates, and geometry dimensions. When a record omits a field, the parser substitutes the corresponding modal value. This mirrors the OASIS specification's stateful design.

### Decoding cells

A single decoder, `CellParserState`, interprets the records of a cell. It doesn't decide what happens to the shapes and placements it decodes, but hands each of them to a *sink*:

- a `ContentsSink` keeps everything, to load a cell;
- an `IndexSink` keeps placements but only counts shapes, to build a [`CellIndex`](@ref OasisTools.CellIndex);
- a `ShapeCallback` passes shapes on to a function, for [`foreach_shape`](@ref);
- a `WriterSink` encodes them into an output file; see [Writing an OASIS file](@ref).

`decode_cell(sink, cell)` feeds a sink from any cell: from memory if the cell is loaded, and from its bytes otherwise, passing everything through the cell's pending edits on the way.

## Lazy loading

Lazy loading is the key feature that distinguishes OasisTools.jl from other OASIS readers.

OASIS files in semiconductor workflows can range from hundreds of megabytes to many gigabytes. A chip-level layout may contain thousands of cells, but a typical analysis task — inspecting a particular standard cell, checking the hierarchy, extracting a sub-block — only needs a handful of them. Fully parsing every cell on load wastes both time and memory.

### How it works

When you call `oasisread(filename; lazy=true)`, the file is memory-mapped and the parser walks through every record to identify cell boundaries (as described above), but the contents of the cells are not decoded. Each [`Cell`](@ref) holds:

- A [`CellSource`](@ref OasisTools.CellSource): a **view** (`SubArray`) into the memory-mapped file buffer, pointing to the raw bytes of the CELL record body, along with the file-level **name reference dictionaries** (cell names and text strings), so that the cell can be decoded independently at any later point. No bytes are copied.
- The cell **name** and **root status**. The unit length is a file-level property, stored on the [`Oasis`](@ref) object rather than per cell.

Because no geometry is decoded and no cell data is copied, opening a file in lazy mode is fast and uses minimal memory beyond the memory-mapped region itself.

### Tiers

What is known about a cell that isn't loaded comes in tiers, reported by [`tier`](@ref):

- **Tier 0:** only where the cell's contents live in the file.
- **Tier 1:** a [`CellIndex`](@ref OasisTools.CellIndex) with the cell's placements and, for every layer and datatype, how many shapes it has. This is enough to work out the cell hierarchy and root cells, and to tell which cells an edit can leave alone.
- **Tier 2:** additionally, the bounding box of the cell's own shapes, which is what [`crop`](@ref) needs.
- **Tier 3:** the cell is loaded.

Nothing needs to be done up front: functions compute what they need on demand, and keep the index with the cell for later. [`placements`](@ref) and [`layer_counts`](@ref) bring a cell to tier 1, [`extent`](@ref) to tier 2. [`index!`](@ref) does so explicitly, for a cell or, in parallel, for all cells. Indexing a cell does decode it, which includes decompressing its compressed blocks, but it doesn't keep its shapes in memory.

### Loading cells on demand

To load the shapes and placements of a cell into memory, use [`load!`](@ref):

```julia
oas = oasisread("large_chip.oas"; lazy=true)
load!(oas[:StandardCell_NAND2])
shapes(oas[:StandardCell_NAND2])
```

To load all cells at once (equivalent to eager mode), use `load!(oas)`.

[`shapes`](@ref) also works on a cell that isn't loaded, but decodes its shapes afresh every time without keeping them. [`foreach_shape`](@ref) goes through them one at a time, for cells too large to hold in memory.

### Editing cells that aren't loaded

Changes to a cell that isn't loaded are recorded as *edits*, rather than loading the cell to carry them out. Whenever the cell is decoded, everything decoded from it passes through its edits: keeping only some shapes ([`filter_shapes!`](@ref)), removing or renaming the placements of a cell ([`remove_cell!`](@ref), [`rename_cell!`](@ref)), adding shapes or placements ([`add_shape!`](@ref), [`add_placement!`](@ref)), and clipping ([`crop`](@ref)). Edits are thus reflected in indexes, in [`shapes`](@ref), when the cell is loaded, and when it is written. Where an index shows that an edit wouldn't change a cell, the cell is left alone.

### Cropping

[`crop`](@ref) uses hierarchical bounding boxes ([`extent`](@ref)) to sort every placement into one of three groups: entirely inside the window (kept as it is), entirely outside (dropped), or crossing its edge. Cells crossing the edge are replaced by cropped copies, which for cells that aren't loaded consist of the original bytes plus edits that clip the shapes and replace the placements. Nothing is loaded in the process.

### Flattening

[`flatten`](@ref) works similarly. The flattened cell is a copy of the original plus one edit, which replaces each placement by the contents of the placed cell, transformed into the coordinates of the flattened cell, recursing as deep as asked. That happens whenever the cell is decoded, so even a flattened layout far too large for memory can be written, one placed cell at a time. Placements and shapes keep their repetitions, combined where possible, so that arrays stay arrays. The shapes of small cells are kept once decoded, so that cells placed many times are only decoded once.

### Root cells

Root cells are those that are not placed inside any other cell. [`roots`](@ref) works them out from the placements of all cells, bringing cells that aren't loaded to tier 1 to find them, so the answer always reflects any edits made since.

Showing an [`Oasis`](@ref) object never decodes anything, so it only shows the cell hierarchy if the placements of all cells are already known, for instance because they were loaded or indexed. Similarly, [`oasiswrite`](@ref) only records the root cells in the optional `S_TOP_CELL` property if it can do so without decoding anything.

## Writing an OASIS file

The entry point for writing is [`oasiswrite`](@ref). The pipeline:

1. **A temporary file.** The output goes to a temporary file in the same directory, which replaces the target once it is complete. A failed write thus leaves an existing file untouched, and the target may even be the file that cells which aren't loaded are being read from: on Linux and macOS, those cells keep seeing the original contents.

2. **Buffered output.** A `WriterState` is created with a large output buffer (16 MB by default). Records are serialized into the buffer and flushed to disk in batches, minimizing the number of write system calls.

3. **Header and name tables.** The magic bytes and START record are written first, followed by file-level properties that declare root cells (`S_TOP_CELL`). Cell names, property names, and layer names follow in a CBLOCK.

4. **Cells.** Each cell is written in turn, starting with its CELL record:
   - **Loaded cells** are serialized from their in-memory shapes and placements.
   - **Cells that aren't loaded and have no pending edits** are handled via *copywriting*: the raw bytes are parsed record by record and copied to the output, translating only the numeric references to cell names and text strings, which are specific to each file. This enables round-tripping files through lazy loading without decoding the geometry of every cell.
   - **Cells with pending edits** are decoded record by record, passed through their edits, and encoded straight into the output, without ever holding the whole cell in memory.

5. **Footer.** The END record closes the file, padded with NUL bytes to exactly 256 bytes as the specification requires.

### Modal variables when writing

Just like a reader, the writer keeps track of modal variables, so that it can leave out fields a reader can infer from earlier records. It resets them at every CELL record, as readers do, and treats them as undefined until they have been written out once. The first records of a cell therefore always spell out their layer, datatype, and so on.

For the same reason, the first path in a cell states explicitly that its ends are flush. Paths are read with any extensions folded into their end points, so they always end flush when written.

### Compressed blocks when writing

With compression enabled (the default; see the `compress` keyword of [`oasiswrite`](@ref)), the records of a cell are written to a temporary `WriterState` backed by an in-memory `IOBuffer`, which shares its modal variables and name references with the main one. Whenever more than about 1 MiB has built up, and at the end of the cell, the accumulated bytes are compressed with DEFLATE and written to the main output as a CBLOCK record. This keeps memory use bounded even for very large cells; as DEFLATE only looks back 32 KiB, larger blocks would hardly compress any better.

Blocks only ever end between records, as a record may not be split across CBLOCKs, and the CELL records themselves stay outside of them, as the specification requires. Cells copied from another file are compressed afresh, rather than keeping their original CBLOCKs, as the name references inside them get translated.
