local DataStorage = require("datastorage")
local has_lfs, lfs = pcall(require, "lfs")
local SourceExportCRE = require("source_export_cre")

local SourceExport = {}

local PASSTHROUGH_EXTENSIONS = {
    md = true,
    markdown = true,
    txt = true,
    pdf = true,
}

local CONVERT_EXTENSIONS = {
    epub = true,
    fb2 = true,
    mobi = true,
    azw = true,
    azw3 = true,
    cbz = true,
    djvu = true,
    doc = true,
    docx = true,
    rtf = true,
}

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function shell_escape(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function mkdir_p(path)
    if has_lfs and lfs.attributes(path, "mode") == "directory" then
        return true
    end
    if has_lfs then
        local current = ""
        for part in tostring(path or ""):gmatch("[^/]+") do
            current = current == "" and (path:sub(1, 1) == "/" and "/" .. part or part) or (current .. "/" .. part)
            if lfs.attributes(current, "mode") ~= "directory" then
                local ok = lfs.mkdir(current)
                if not ok and lfs.attributes(current, "mode") ~= "directory" then
                    return nil, "Could not create source export directory: " .. current
                end
            end
        end
        return true
    end
    local ok = os.execute("mkdir -p " .. shell_escape(path))
    if ok == true or ok == 0 then
        return true
    end
    return nil, "Could not create source export directory."
end

function SourceExport.extension(path)
    return tostring(path or ""):match("%.([^%.%s/]+)$")
end

function SourceExport.normalized_extension(path)
    local ext = SourceExport.extension(path)
    return ext and ext:lower() or ""
end

function SourceExport.sanitize_filename(value, fallback)
    local name = trim(value)
    if name == "" then
        name = fallback or "book"
    end
    name = name:gsub("[/\\:*?\"<>|]+", " ")
    name = name:gsub("[%c]+", " ")
    name = name:gsub("%s+", " ")
    name = trim(name)
    if name == "" then
        name = fallback or "book"
    end
    if #name > 96 then
        name = trim(name:sub(1, 96))
    end
    return name
end

function SourceExport.is_passthrough(path)
    return PASSTHROUGH_EXTENSIONS[SourceExport.normalized_extension(path)] == true
end

function SourceExport.should_convert(path)
    return CONVERT_EXTENSIONS[SourceExport.normalized_extension(path)] == true
end

local function output_dir(opts)
    opts = opts or {}
    return opts.output_dir or (DataStorage:getSettingsDir() .. "/notebooklm-sources")
end

local function output_path(book, opts)
    local base = SourceExport.sanitize_filename((book and book.title) or "book", "book")
    local stamp = os.date("!%Y%m%dT%H%M%SZ") .. "-" .. tostring(math.floor((os.clock() or 0) * 1000))
    return output_dir(opts) .. "/" .. base .. "-" .. stamp .. ".md"
end

local function write_file(path, body)
    local file, err = io.open(path, "wb")
    if not file then
        return nil, "Could not write source export: " .. tostring(err or path)
    end
    file:write(body)
    file:close()
    return true
end

local function file_size(path)
    local file = io.open(path or "", "rb")
    if not file then
        return nil
    end
    local size = file:seek("end")
    file:close()
    return size
end

local function basename(path)
    return tostring(path or ""):match("([^/]+)$") or tostring(path or "source")
end

function SourceExport.prepare(book, document, opts)
    opts = opts or {}
    book = book or {}
    local source_path = tostring(book.path or "")
    if source_path == "" then
        return nil, "This book does not expose a file path for upload."
    end
    if SourceExport.is_passthrough(source_path) then
        return {
            file_path = source_path,
            source_title = book.title,
            method = "passthrough-" .. SourceExport.normalized_extension(source_path),
            temporary = false,
            byte_count = file_size(source_path),
        }
    end
    if not SourceExport.should_convert(source_path) and not document then
        return nil, "Unsupported file extension for upload: " .. SourceExport.normalized_extension(source_path)
    end

    local extracted, extract_err = SourceExportCRE.extract(document, opts)
    if not extracted then
        return nil, extract_err or "Could not extract this book through KOReader."
    end
    local dir = output_dir(opts)
    local ok, mkdir_err = mkdir_p(dir)
    if not ok then
        return nil, mkdir_err
    end
    local path = output_path(book, opts)
    local title = SourceExport.sanitize_filename(book.title or "KOReader source", "KOReader source")
    local body = table.concat({
        "# " .. title,
        "",
        extracted.text,
        "",
    }, "\n")
    local wrote, write_err = write_file(path, body)
    if not wrote then
        return nil, write_err
    end
    return {
        file_path = opts.prefer_original and source_path or path,
        source_title = opts.prefer_original and basename(source_path) or (title .. ".md"),
        method = opts.prefer_original and ("original-" .. SourceExport.normalized_extension(source_path)) or extracted.method,
        temporary = not opts.prefer_original,
        byte_count = opts.prefer_original and file_size(source_path) or file_size(path),
        char_count = extracted.char_count,
        page_count = extracted.page_count,
        fallback = opts.prefer_original and {
            file_path = path,
            source_title = title .. ".md",
            method = extracted.method,
            temporary = true,
            byte_count = file_size(path),
            char_count = extracted.char_count,
            page_count = extracted.page_count,
        } or nil,
    }
end

return SourceExport
