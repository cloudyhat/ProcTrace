
# ProcTrace
_A SQL-powered stored procedure dependency & mutation tracker._

## Overview
ProcTrace is a single SQL script that scans a target database/schema and emits a **flat report** of stored procedure dependencies alongside **mutation flags** (whether any called procedures perform `INSERT` or `UPDATE` operations).  
The result is exported as **CSV** (and optionally Excel) so you can filter, pivot, and share easily.

By default, mutation flags are set for `INSERT` and `UPDATE` statements.  
You can extend ProcTrace to detect other SQL commands by adding them to the pattern matching logic in the script, 
for example:
- **`DELETE`** – Remove rows from a table.  
- **`MERGE`** – Conditional insert/update/delete in one statement.  
- **`TRUNCATE`** – Fast table clear.  
- **`DROP`** – Object removal (if you want to track schema changes too). 

## What ProcTrace Outputs

ProcTrace returns one row per _dependency edge_ (RootProc → CalledSPs) with these columns:

| Column            | Type        | Meaning |
|-------------------|-------------|---------|
| **Procedure**     | `sysname`   | The root stored procedure being analyzed (`RootProc`). |
| **Calls_These_SPs** | `sysname` | The stored procedure that `Procedure` calls (`CalledSPs`). One row per call target. |
| **AnyInsert**     | `bit/Yes-No`| `Yes` if either `Procedure` _or_ `Calls_These_SPs` contains an `INSERT` (direct or nested, depending on recursion depth configured). |
| **AnyUpdate**     | `bit/Yes-No`| `Yes` if either `Procedure` _or_ `Calls_These_SPs` contains an `UPDATE` (direct or nested, depending on recursion depth configured). |
| **DML_Lines**     | `nvarchar`  | Semicolon-separated line numbers (or short code excerpts) within the relevant procedure(s) where DML was detected. Empty when no DML found. |