if vim.g.loaded_sqlua then
    return
end

vim.g.loaded_sqlua = true

-- Track whether setup() has been called
local _sqlua_setup_done = false

-- Ensure setup runs only once
local function ensure_setup()
    if not _sqlua_setup_done then
        require("sqlua").setup()
        _sqlua_setup_done = true
    end
end

vim.cmd('command! SQLua lua require("sqlua").setup()')

-- SQLuaOpen command (works before setup)
vim.api.nvim_create_user_command("SQLuaOpen", function(args)
    ensure_setup()
    -- Delegate to the SQLuaOpen command created during setup
    vim.cmd("SQLuaOpen " .. (args.args or ""))
end, { nargs = "?", complete = "file" })

-- Auto-open database files
-- Uses VimEnter for files passed as CLI args, and BufEnter for files opened later
local db_extensions = { "db", "sqlite", "sqlite3", "s3db" }

local function is_db_file(filepath)
    local ext = (filepath:match("%.([^%.]+)$") or ""):lower()
    for _, db_ext in ipairs(db_extensions) do
        if ext == db_ext then return true end
    end
    return false
end

local function open_db_file(filepath)
    ensure_setup()
    local dbfile = require("sqlua.dbfile")
    local config = DEFAULT_CONFIG or {}
    dbfile.prompt_and_open(filepath, config)
end

-- Handle db files passed as command line arguments (nvim file.db)
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        local args = vim.fn.argv()
        for _, arg in ipairs(args) do
            if is_db_file(arg) then
                local filepath = vim.fn.fnamemodify(arg, ":p")
                if vim.fn.filereadable(filepath) == 1 then
                    -- Defer to after VimEnter completes
                    vim.schedule(function()
                        open_db_file(filepath)
                    end)
                    return
                end
            end
        end
    end,
    once = true,
})

-- Handle db files opened during a session (:e file.db)
vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(ev)
        local bufname = vim.api.nvim_buf_get_name(ev.buf)
        if bufname == "" then return end
        if not is_db_file(bufname) then return end
        -- Skip if SQLua UI is already loaded
        local UI = require("sqlua.ui")
        if UI.initial_layout_loaded then return end

        local filepath = vim.fn.fnamemodify(bufname, ":p")
        if vim.fn.filereadable(filepath) == 1 then
            vim.schedule(function()
                open_db_file(filepath)
            end)
        end
    end,
})
