# CLAUDE.md

Read `AGENTS.md` for the project development guide.

## J Code Munch

Use `jcodemunch` for code discovery before native file tools.

Start repository work by calling `resolve_repo` for the current directory. If the repo is not indexed, call `index_folder`.

Prefer:
- `search_symbols` for functions, classes, methods, and identifiers
- `search_text` for literals, comments, configs, and TODOs
- `get_repo_outline` and `get_file_tree` for structure
- `get_file_outline` before reading whole source files
- `get_symbol_source`, `get_context_bundle`, or `get_ranked_context` for targeted source context
- `index_file` after editing source files
