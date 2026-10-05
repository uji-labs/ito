stds.luajit52 = {
    read_globals = {
        package = { fields = { "searchers" } },
        table = { fields = { "unpack" } },
    },
}

std = "luajit+luajit52"
self = false
max_line_length = false
exclude_files = { "tests/vendor" }

files["tests/*_spec.lua"] = {
    read_globals = {
        "after_each",
        "before_each",
        "describe",
        "it",
        assert = { other_fields = true },
    },
}
