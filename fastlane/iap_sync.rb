# Syncs in-app purchase AND auto-renewable subscription localizations on App
# Store Connect to match fastlane/iap_localizations.json. Uses the App Store
# Connect API directly — deliver does not manage IAP metadata. Invoked by the
# `sync_iap` lane.
#
# One-time IAPs and subscriptions are distinct ASC resources with parallel but
# separate localization endpoints (inAppPurchaseLocalizations vs
# subscriptionLocalizations); both carry the same name/description/locale shape,
# so the per-locale sync is shared and only the endpoints differ (see ENDPOINTS).
#
# This script only syncs LOCALIZATIONS of products that already exist on ASC —
# it never creates products. Create product 09, the "Pro" subscription group,
# and the subscriptions (with pricing) manually in App Store Connect first; a
# product ID not found on ASC is skipped.
#
# ASC state model: a localization in a live/immutable state (ACTIVE/APPROVED) is
# not editable — posting a NEW localization for the same locale creates the
# pending edit that goes to review with the next submission. Editable states
# (PREPARE_FOR_SUBMISSION, REJECTED) are patched in place.
require "net/http"
require "json"

module IapSync
  BASE = "https://api.appstoreconnect.apple.com".freeze
  EDITABLE_STATES = %w[PREPARE_FOR_SUBMISSION REJECTED].freeze

  # Per-resource localization endpoints. `list` is relative to the parent
  # product; `rel` is the create-time relationship to that product.
  ENDPOINTS = {
    iap: {
      list: ->(id) { "/v2/inAppPurchases/#{id}/inAppPurchaseLocalizations?limit=200" },
      collection: "/v1/inAppPurchaseLocalizations",
      type: "inAppPurchaseLocalizations",
      rel: ->(id) { { inAppPurchaseV2: { data: { type: "inAppPurchases", id: id } } } },
    },
    subscription: {
      list: ->(id) { "/v1/subscriptions/#{id}/subscriptionLocalizations?limit=200" },
      collection: "/v1/subscriptionLocalizations",
      type: "subscriptionLocalizations",
      rel: ->(id) { { subscription: { data: { type: "subscriptions", id: id } } } },
    },
  }.freeze

  def self.run(bearer_token)
    @bearer = bearer_token
    failures = []
    data = JSON.parse(File.read(File.join(__dir__, "iap_localizations.json")))

    app = req(:get, "/v1/apps?filter[bundleId]=#{data.fetch('bundle_id')}")
      .fetch("data").first or raise "app not found for #{data['bundle_id']}"

    # productId -> { kind:, id: } across both one-time IAPs and subscriptions.
    products = {}
    req(:get, "/v1/apps/#{app['id']}/inAppPurchasesV2?limit=200").fetch("data").each do |iap|
      products[iap.dig("attributes", "productId")] = { kind: :iap, id: iap["id"] }
    end
    subscriptions_for(app["id"]).each do |sub|
      products[sub.dig("attributes", "productId")] = { kind: :subscription, id: sub["id"] }
    end

    data.fetch("products").each do |product_id, locales|
      product = products[product_id]
      unless product
        puts "SKIP product #{product_id}: not found on App Store Connect"
        next
      end
      endpoints = ENDPOINTS.fetch(product[:kind])
      existing = req(:get, endpoints[:list].call(product[:id]))
        .fetch("data")
        .group_by { |l| l.dig("attributes", "locale") }

      locales.each do |locale, strings|
        sync_locale(product_id, product[:id], endpoints, locale, strings, existing, failures)
      end
    end
    raise "sync failed for: #{failures.join(', ')}" unless failures.empty?
  end

  # All subscriptions across the app's subscription groups.
  def self.subscriptions_for(app_id)
    resp = req(:get, "/v1/apps/#{app_id}/subscriptionGroups?include=subscriptions&limit=200")
    (resp["included"] || []).select { |r| r["type"] == "subscriptions" }
  end

  def self.sync_locale(product_id, resource_id, endpoints, locale, strings, existing, failures)
    attrs = { "name" => strings.fetch("name"), "description" => strings.fetch("description") }
    group = existing[locale] || []
    editable = group.find { |l| EDITABLE_STATES.include?(l.dig("attributes", "state")) }
    target = editable || group.first
    state = target&.dig("attributes", "state")
    begin
      if target && target["attributes"].values_at("name", "description") == attrs.values_at("name", "description")
        puts "ok      #{product_id} #{locale}"
      elsif editable
        req(:patch, "#{endpoints[:collection]}/#{editable['id']}", {
          data: { type: endpoints[:type], id: editable["id"], attributes: attrs },
        })
        puts "UPDATED #{product_id} #{locale}"
      else
        # No editable entry: either the locale is new, or only an immutable
        # live entry exists — POST creates the (pending) localization.
        req(:post, endpoints[:collection], {
          data: {
            type: endpoints[:type],
            attributes: attrs.merge("locale" => locale),
            relationships: endpoints[:rel].call(resource_id),
          },
        })
        puts group.empty? ? "CREATED #{product_id} #{locale}" : "EDITED  #{product_id} #{locale} (pending review)"
      end
    rescue => e
      puts "FAILED  #{product_id} #{locale} (state=#{state}): #{e.message.lines.first&.strip}"
      failures << "#{product_id} #{locale}"
    end
  end

  def self.req(method, path, body = nil)
    uri = URI("#{BASE}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
    request = klass.new(uri)
    request["Authorization"] = "Bearer #{@bearer}"
    request["Content-Type"] = "application/json"
    request.body = body.to_json if body
    response = http.request(request)
    unless response.code.to_i < 300
      raise "#{method.upcase} #{path} -> HTTP #{response.code}: #{response.body}"
    end
    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  end
end
