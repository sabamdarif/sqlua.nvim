local utils = require("sqlua.utils")
local Connection = require("sqlua.connection")

local M = {}

--- File extensions that are auto-detected as SQLite databases
local SQLITE_EXTENSIONS = { "db", "sqlite", "sqlite3", "s3db" }

--- All supported DBMS types for the selection prompt
local DBMS_CHOICES = { "SQLite", "PostgreSQL", "MySQL", "MariaDB", "Snowflake" }

--- Get file extension from a path
---@param filepath string
---@return string
local function get_extension(filepath)
    return filepath:match("%.([^%.]+)$") or ""
end

--- Get filename without extension from a path
---@param filepath string
---@return string
local function get_basename(filepath)
    local name = filepath:match("([^/\\]+)$") or filepath
    return name:match("(.+)%..+$") or name
end

--- Check if a file extension matches known SQLite extensions
---@param ext string
---@return boolean
local function is_sqlite_extension(ext)
    ext = ext:lower()
    for _, sqlite_ext in ipairs(SQLITE_EXTENSIONS) do
        if ext == sqlite_ext then return true end
    end
    return false
end

--- Setup and launch SQLua with a given connection
---@param name string connection name
---@param url string connection url
---@param config table plugin config
local function launch_sqlua(name, url, config)
    local UI = require("sqlua.ui")

    -- Save to connections.json so it persists
    Connection.add(url, name)

    -- If UI is not yet initialized, set it up
    if not UI.initial_layout_loaded then
        UI:setup(config)
        UI.initial_layout_loaded = true
    end

    -- Load all connections (including the new one)
    local cons = Connection.read()
    for _, con in pairs(cons) do
        local cname, curl = con["name"], con["url"]
        if not UI.dbs[cname] then
            vim.fn.mkdir(SQLUA_ROOT_DIR .. "/" .. cname, "p")
            local connection = Connection.setup(cname, curl, UI.options or config)
            if config.load_connections_on_start and connection then connection:connect() end
            UI.dbs[cname] = connection
        end
    end

    -- Set the newly added db as active
    UI.active_db = name

    -- Connect if not already connected
    if UI.dbs[name] and not UI.dbs[name].loaded then
        UI.dbs[name]:connect()
    end

    if UI.num_dbs > 0 then
        vim.api.nvim_win_set_cursor(UI.windows.sidebar, { 2, 2 })
    end
    UI:refreshSidebar()
end

--- Handle opening a SQLite database directly from a file path
---@param filepath string absolute path to the .db file
---@param config table plugin config
local function open_sqlite(filepath, config)
    local name = get_basename(filepath)
    -- Check if this connection already exists
    local existing = Connection.read()
    for _, con in pairs(existing) do
        if con["url"] == filepath then
            -- Connection already exists, just launch with it
            launch_sqlua(con["name"], con["url"], config)
            return
        end
    end
    launch_sqlua(name, filepath, config)
end

--- Prompt the user for a connection URL and name, then open the database
---@param dbms_label string human-readable DBMS name
---@param config table plugin config
local function prompt_connection_details(dbms_label, config)
    local prefix_map = {
        PostgreSQL = "postgres",
        MySQL = "mysql",
        MariaDB = "mariadb",
        Snowflake = "snowflake",
    }

    local prefix = prefix_map[dbms_label]

    if dbms_label == "Snowflake" then
        vim.ui.input({ prompt = "Connection name: " }, function(name)
            if not name or name == "" then
                vim.notify("SQLua: Connection cancelled.", vim.log.levels.WARN)
                return
            end
            launch_sqlua(name, "snowflake", config)
        end)
        return
    end

    vim.ui.input({
        prompt = string.format("Enter %s connection URL (e.g. %s://user:pass@host:port/dbname): ", dbms_label, prefix),
    }, function(url)
        if not url or url == "" then
            vim.notify("SQLua: Connection cancelled.", vim.log.levels.WARN)
            return
        end
        vim.ui.input({
            prompt = "Connection name (leave empty for auto): ",
        }, function(name)
            if not name or name == "" then
                -- Try to extract database name from URL
                local parsed = utils.parse_jdbc(url)
                if parsed and parsed.database then
                    name = parsed.database
                else
                    name = "db_" .. os.time()
                end
            end
            launch_sqlua(name, url, config)
        end)
    end)
end

--- Main entry point: detect DBMS from file and prompt if needed
---@param filepath string absolute path to the file being opened
---@param config table plugin config
function M.prompt_and_open(filepath, config)
    local ext = get_extension(filepath)

    -- Auto-detect SQLite by extension
    if is_sqlite_extension(ext) then
        open_sqlite(filepath, config)
        return
    end

    -- For other extensions, prompt the user to select the DBMS
    vim.ui.select(DBMS_CHOICES, {
        prompt = "Select database type for: " .. vim.fn.fnamemodify(filepath, ":t"),
    }, function(choice)
        if not choice then
            vim.notify("SQLua: No database type selected.", vim.log.levels.WARN)
            return
        end

        if choice == "SQLite" then
            open_sqlite(filepath, config)
        else
            prompt_connection_details(choice, config)
        end
    end)
end

return M
