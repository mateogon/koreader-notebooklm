-- Example KOReader plugin settings.
-- Do not include credentials.

return {
    backend = "bridge",
    bridge_url = "http://127.0.0.1:8765",
    timeout = 120,
    enable_upload = true,
    upload_mode = "multipart",
    show_prompt_buttons = true,
}
