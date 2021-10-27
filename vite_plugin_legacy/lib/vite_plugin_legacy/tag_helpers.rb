# frozen_string_literal: true

# Public: Allows to render HTML tags for scripts and styles processed by Vite.
module VitePluginLegacy::TagHelpers
  VITE_SAFARI_NOMODULE_FIX = <<-JS.html_safe.freeze
  !function(){var e=document,t=e.createElement("script");if(!("noModule"in t)&&"onbeforeload"in t){var n=!1;e.addEventListener("beforeload",(function(e){if(e.target===t)n=!0;else if(!e.target.hasAttribute("nomodule")||!n)return;console.log('preventing load',e.target);e.preventDefault()}),!0),t.type="module",t.src=".",e.head.appendChild(t),t.remove()}}();
  JS
  # Public: Renders a <script> tag for the specified Vite entrypoints when using
  # @vitejs/plugin-legacy, which injects polyfills.
  def vite_legacy_javascript_tag(name, asset_type: :javascript)
    return if ViteRuby.instance.dev_server_running?

    legacy_name = name.sub(/(\..+)|$/, '-legacy\1')

    import_tag = content_tag(:script, nomodule: true) {
      vite_legacy_import_body(name, asset_type: asset_type)
    }

    import_tag
  end

  # Public: Same as `vite_legacy_javascript_tag`, but for TypeScript entries.
  def vite_legacy_typescript_tag(name)
    vite_legacy_javascript_tag(name, asset_type: :typescript)
  end

  # Renders the vite-legacy-polyfill to enable code splitting in
  # browsers that do not support modules.
  # entrypoints: { "entrypoint_name" => asset_type }
  # e.g.: { "application" => :typescript }
  # must come before all other vite import tags
  def vite_legacy_polyfill_tag(entrypoints)
    return if ViteRuby.instance.dev_server_running?

    name = vite_manifest.send(:manifest).keys.find { |file| file.include?('legacy-polyfills') } ||
           raise(ArgumentError, 'Vite legacy polyfill not found in manifest.json')

    tags = []
    safari_nomodule_fix = content_tag(:script, nil, nomodule: true) { VITE_SAFARI_NOMODULE_FIX }
    tags.push(safari_nomodule_fix)
    # for browsers which do not support modules at all
    legacy_polyfill = content_tag(:script, nil, nomodule: true, id: 'vite-legacy-polyfill', src: vite_asset_path(name))
    tags.push(legacy_polyfill)
    # for browsers which support modules, but don't support dynamic import
    legacy_fallback_tag = content_tag(:script, nil, type: 'module') do
      vite_dynamic_fallback_inline_code(entrypoints)
    end
    tags.push(legacy_fallback_tag)
    safe_join(tags, "\n")
  end

  def vite_dynamic_fallback_inline_code(entrypoints)
    load_body = entrypoints.map do |name, asset_type|
      vite_legacy_import_body(name, asset_type: asset_type)
    end
    load_body = safe_join(load_body, "\n")
    %Q{!function(){try{new Function("m","return import(m)")}catch(o){console.warn("vite: loading legacy build because dynamic import is unsupported, syntax error above should be ignored");var e=document.getElementById("vite-legacy-polyfill"),n=document.createElement("script");n.src=e.src,n.onload=function(){#{load_body}},document.body.appendChild(n)}}();}.html_safe
  end

  def vite_legacy_import_body(name, asset_type: :javascript)
    legacy_name = name.sub(/(\..+)|$/, '-legacy\1')
    "System.import('#{ vite_asset_path(legacy_name, type: asset_type) }')".html_safe
  end
end
