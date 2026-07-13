# The OASIS File Format

## What is OASIS?

OASIS (Open Artwork System Interchange Standard) is a binary file format for representing integrated circuit (IC) layout data. It's the successor to GDSII, the long-standing industry standard dating back to the 1970s.

OASIS was designed to address the limitations of GDSII as IC designs grew in complexity. Modern layouts can contain billions of geometric shapes, and GDSII's fixed-width fields and lack of compression make it poorly suited to handle files of this scale. OASIS achieves dramatically smaller file sizes through a combination of variable-length integer encoding, modal (stateful) fields, repetition structures, and compression.

The format is used throughout the semiconductor manufacturing pipeline: by design tools that generate layout data, by mask data preparation (MDP) software that processes it, and by mask writing equipment that transfers it to physical photomasks.

## File structure

An OASIS file is a flat sequence of **records**, each beginning with a record-type byte that identifies what kind of data follows. The file has the following overall structure:

```
Magic bytes ("%SEMI-OASIS\r\n")
START record
  ├─ Table offsets
  ├─ File-level records (CELLNAME, LAYERNAME, PROPNAME, ...)
  ├─ CELL records
  │   ├─ Geometry records (RECTANGLE, POLYGON, PATH, ...)
  │   ├─ PLACEMENT records
  │   └─ TEXT records
  └─ CBLOCK records (compressed wrappers around any of the above)
END record
```

### Record types

The most important record types are:

| Type byte | Name | Description |
|-----------|------|-------------|
| 1 | START | File header. Contains format version, unit (grid steps per micron), and byte offsets to name/string tables. |
| 2 | END | File footer. Contains an optional validation signature or checksum. |
| 3, 4 | CELLNAME | Declares a cell name, either inline or as a numeric reference for compact later use. |
| 11, 12 | LAYERNAME | Associates a human-readable name with a range of layer/datatype numbers. |
| 13, 14 | CELL | Begins a cell definition. All geometry, placement, and text records that follow belong to this cell, until the next CELL or END record. |
| 17, 18 | PLACEMENT | Places an instance of another cell, with optional location offset, rotation, magnification, x-axis reflection, and repetition. |
| 20 | RECTANGLE | An axis-aligned rectangle. |
| 21 | POLYGON | A polygon defined by a point list. |
| 28, 29 | PROPERTY | An annotation element supplying descriptive information about the characteristics of the OASIS file or one of its components.
| 34 | CBLOCK | A DEFLATE-compressed block wrapping a sequence of other records. |

## Key design features

### Compact integer encoding

OASIS encodes unsigned integers using a variable-length scheme: each byte contributes 7 data bits, with the most significant bit serving as a continuation flag. Small values (0–127) fit in a single byte; larger values grow as needed.

Signed integers are encoded by mapping the sign into the least significant bit (even values are non-negative, odd values are negative), so that small magnitudes remain compact regardless of sign.

### Modal variables

The format is stateful. Most fields within geometry and placement records are optional. If a field is omitted, the parser reuses the last value it saw for that field. These cached values are called **modal variables**. For example, if several consecutive rectangles share the same layer and datatype, those fields only need to appear in the first record. This is one of the largest contributors to OASIS's compactness.

### Repetitions

Shapes and placements can carry a repetition specification rather than being duplicated. OASIS defines several repetition types:

- Regular grids: `n × m` instances spaced by constant step vectors.
- Non-uniform sequences: a list of offsets along one axis or in the general plane.

This means a single record can represent thousands or millions of identical instances arranged in a grid — common in memory arrays, standard cell rows, and via patterns.

### Compressed blocks (CBLOCKs)

Any contiguous sequence of records can be wrapped in a CBLOCK record, which stores the records in DEFLATE-compressed form. This provides an additional layer of size reduction on top of the format's inherent compactness, and allows OASIS writers to selectively compress portions of the file.

### Name references

Cell names, text strings, property names, and property values can be assigned numeric IDs (via the `*NAME` and `*STRING` records) and subsequently referenced by number. This avoids repeating long strings throughout the file.

### Strict vs. non-strict mode

The START record contains a `table-offsets` field that can point to the byte locations of the name and string tables (CELLNAME, TEXTSTRING, PROPNAME, PROPSTRING, LAYERNAME). This field controls whether the file is in strict or non-strict mode:

- Non-strict mode: all table offsets are zero. Name and string records can appear anywhere in the file, interleaved with cell definitions and other records. A reader must scan the entire file before it can resolve all references.
- Strict mode: the table offsets are nonzero and point to the exact byte locations of the tables. The tables are guaranteed to appear either before all CELL records or in a dedicated table section at the end of the file (between the last CELL and the END record). This allows readers to jump directly to the tables without a full sequential scan.

Strict mode exists to facilitate random access and partial reading, but in practice many OASIS writers produce non-strict files. OasisTools.jl does not require strict mode; it always scans the full file sequentially.

### Standard properties

OASIS defines a set of standard file-level properties with reserved names (prefixed `S_`). One notable reserved property is **`S_TOP_CELL`**: a file-level PROPERTY record that declares a cell as a top-level (root) cell. An OASIS file may contain zero, one, or many `S_TOP_CELL` properties. This property is optional; there is no guarantee that a given file includes it. When absent, a reader must infer root cells by other means (e.g., by checking which cells are not placed inside any other cell).
