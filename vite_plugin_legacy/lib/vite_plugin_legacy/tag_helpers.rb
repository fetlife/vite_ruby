# frozen_string_literal: true

# Public: Allows to render HTML tags for scripts and styles processed by Vite.
module VitePluginLegacy::TagHelpers
  VITE_SAFARI_NOMODULE_FIX = <<-JS.html_safe.freeze
  !function(){var e=document,t=e.createElement("script");if(!("noModule"in t)&&"onbeforeload"in t){var n=!1;e.addEventListener("beforeload",(function(e){if(e.target===t)n=!0;else if(!e.target.hasAttribute("nomodule")||!n)return;e.preventDefault()}),!0),t.type="module",t.src=".",e.head.appendChild(t),t.remove()}}();
  JS
  LEGACY_POLYFILL_ID = 'vite-legacy-polyfill'
  LEGACY_ENTRY_ID = 'vite-legacy-entry'
  DETECT_MODERN_BROWSER_VAR_NAME = '__vite_is_modern_browser'
  DETECT_MODERN_BROWSER_DETECTOR = <<-JS.html_safe.freeze
  import.meta.url;import("_").catch(()=>1);async function* g(){};
  JS
  DETECT_MODERN_BROWSER_CODE = <<-JS.html_safe.freeze
  #{DETECT_MODERN_BROWSER_DETECTOR}if(location.protocol!="file:"){window.#{DETECT_MODERN_BROWSER_VAR_NAME}=true}
  JS


  # Renders code to load vite entrypoints for legacy browsers:
  # * Safari NOMODULE fix for Safari 10, which supports modules but not `nomodule`
  # * vite-legacy-polyfill (System.import polyfill) for browsers that do not support modules @vitejs/plugin-legacy
  # * Dynamic import code for browsers that support modules, but not dynamic imports
  # This helper must be called before any other Vite import tags.
  # Accepts a hash with entrypoint names as keys and asset types (:javascript or :typescript) as values.
  def vite_legacy_javascript_tag(entrypoints)
    return if ViteRuby.instance.dev_server_running?

    tags = []
    # TODO: we need to inject modern polyfills (legacy-polyfills) only if present
    # // 2. inject Safari 10 nomodule fix
    safari_nomodule_fix = content_tag(:script, nil, nomodule: true) { VITE_SAFARI_NOMODULE_FIX }
    tags.push(safari_nomodule_fix)
    # // 3. inject legacy polyfills
    # for browsers which do not support modules at all
    legacy_polyfill = content_tag(:script, nil, nomodule: true, id: LEGACY_POLYFILL_ID, src: vite_asset_path('legacy-polyfills-legacy', type: :virtual))
    tags.push(legacy_polyfill)
    # // 4. inject legacy entry
    entrypoints.each do |name, asset_type|
      import_tag = content_tag(:script, nomodule: true) do
        vite_system_js_inline_code(name, asset_type: asset_type)
      end
      tags.push(import_tag)
    end
    # for browsers which support modules, but don't support dynamic import or new syntax (safari 11.1)
    tags.push(content_tag(:script, nil, type: 'module') { DETECT_MODERN_BROWSER_CODE })
    #  // 5. inject dynamic import fallback entry
    legacy_fallback_tag = content_tag(:script, nil, type: 'module') do
      vite_dynamic_fallback_inline_code(entrypoints)
    end
    tags.push(legacy_fallback_tag)
    safe_join(tags, "\n")
  end

  def vite_dynamic_fallback_inline_code(entrypoints)
    load_body = entrypoints.map do |name, asset_type|
      vite_system_js_inline_code(name, asset_type: asset_type)
    end
    load_body = safe_join(load_body, "\n")
    # rubocop:disable Layout/LineLength
    %{!function(){if(window.#{DETECT_MODERN_BROWSER_VAR_NAME})return;console.warn("vite: loading legacy chunks, syntax error above and the same error below should be ignored");var e=document.getElementById("#{LEGACY_POLYFILL_ID}"),n=document.createElement("script");n.src=e.src,n.onload=function(){#{ load_body }},document.body.appendChild(n)}();}.html_safe
    # rubocop:enable Layout/LineLength
  end

  def vite_system_js_inline_code(name, asset_type: :javascript)
    "System.import('#{ vite_asset_path(vite_legacy_name(name), type: asset_type) }')".html_safe
  end

  def vite_legacy_name(name)
    name.sub(/(\..+)|$/, '-legacy\1')
  end
end
