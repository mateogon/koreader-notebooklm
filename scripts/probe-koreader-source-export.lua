-- Run from a KOReader runtime directory with its bundled luajit:
--   ./luajit /path/to/scripts/probe-koreader-source-export.lua /path/to/book.epub
--
-- This opens the document through KOReader providers, exports it with the
-- NotebookLM plugin source exporter, and prints compact quality samples.

local script_path = arg and arg[0] or ""
local repo_root = script_path:gsub("/scripts/probe%-koreader%-source%-export%.lua$", "")
local plugin_path = repo_root .. "/plugin/notebooklm.koplugin"

local function basename(path)
    return tostring(path or ""):match("([^/]+)$") or tostring(path or "book")
end

local function title_from_path(path)
    local name = basename(path):gsub("%.[^%.]+$", "")
    name = name:gsub("[_%-%s]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or "KOReader source"
end

local function init_koreader()
    dofile("setupkoenv.lua")
    G_defaults = require("luadefaults"):open()
    local DataStorage = require("datastorage")
    G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
    local Device = require("device")
    local CanvasContext = require("document/canvascontext")
    CanvasContext:init(Device)
end

local function read_lines(path)
    local file = assert(io.open(path, "rb"))
    local body = file:read("*all")
    file:close()
    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    return body, lines
end

local function compact(line)
    line = tostring(line or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #line > 180 then
        line = line:sub(1, 177) .. "..."
    end
    return line
end

local function count_lines(lines, pattern)
    local count = 0
    for _, line in ipairs(lines) do
        if line:find(pattern) then
            count = count + 1
        end
    end
    return count
end

local function non_empty_sample(lines, target)
    if #lines == 0 then
        return nil
    end
    target = math.max(1, math.min(#lines, target))
    for offset = 0, 20 do
        local down = lines[target + offset]
        if down and compact(down) ~= "" then
            return target + offset, compact(down)
        end
        local up = lines[target - offset]
        if up and compact(up) ~= "" then
            return target - offset, compact(up)
        end
    end
    return target, ""
end

local function probe(path, output_dir)
    local DocumentRegistry = require("document/documentregistry")
    local SourceExport = require("source_export")
    local provider = DocumentRegistry:getProvider(path)
    local document, open_err = DocumentRegistry:openDocument(path, provider)
    if not document then
        return nil, "open failed: " .. tostring(open_err)
    end

    local started = os.clock()
    local source, export_err = SourceExport.prepare({
        path = path,
        title = title_from_path(path),
    }, document, {
        output_dir = output_dir,
    })
    local elapsed = os.clock() - started

    if document.close then
        document:close()
    end
    if not source then
        return nil, export_err
    end

    local body, lines = read_lines(source.file_path)
    return {
        source = source,
        elapsed = elapsed,
        bytes = #body,
        line_count = #lines,
        html_tag_lines = count_lines(lines, "<[/!A-Za-z][^>]*>"),
        entity_lines = count_lines(lines, "&[#A-Za-z0-9]+;"),
        replacement_lines = count_lines(lines, "\239\191\189"),
        control_lines = count_lines(lines, "[%z\1-\8\11\12\14-\31]"),
        lines = lines,
    }
end

init_koreader()
package.path = plugin_path .. "/?.lua;" .. package.path

local output_dir = os.getenv("KOREADER_NOTEBOOKLM_EXPORT_PROBE_DIR") or "/tmp/notebooklm-real-export-validation"
for i = 1, #arg do
    local path = arg[i]
    if path and path ~= "" then
        local result, err = probe(path, output_dir)
        if not result then
            print("FAIL", path, err)
        else
            print("FILE", path)
            print("EXPORT", result.source.file_path)
            print("METHOD", result.source.method)
            print("TITLE", result.source.source_title)
            print("BYTES", result.bytes)
            print("LINES", result.line_count)
            print("CHARS", result.source.char_count or "")
            print("SECONDS", string.format("%.3f", result.elapsed))
            print("HTML_TAG_LINES", result.html_tag_lines)
            print("ENTITY_LINES", result.entity_lines)
            print("REPLACEMENT_LINES", result.replacement_lines)
            print("CONTROL_LINES", result.control_lines)
            local sample_targets = { 1, 20, 100, 200, 300, math.floor(result.line_count / 2), result.line_count - 100, result.line_count }
            for _, target in ipairs(sample_targets) do
                if target >= 1 and target <= result.line_count then
                    local line_no, line = non_empty_sample(result.lines, target)
                    print("SAMPLE", line_no, line)
                end
            end
        end
    end
end
