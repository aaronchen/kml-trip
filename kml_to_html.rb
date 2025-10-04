#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'open-uri'
require 'json'
require 'net/http'
require 'dotenv'
require 'base64'

Dotenv.load

mid = ARGV[0]
file = ARGV[1]

if !mid || !file
  puts 'Usage: kml_to_html mid file'
  exit
end

# To find Place ID for POIs, go to:
#   https://developers.google.com/places/place-id
# Later, Edit POIs and put 'PLACEID:place_id' in POI description

def fetch_place_id(name, lat, lng, api_key)
  url = URI("https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=#{lat},#{lng}&radius=100&type=point_of_interest&keyword=#{URI.encode_www_form_component(name)}&key=#{api_key}")
  res = Net::HTTP.get_response(url)
  if res.is_a?(Net::HTTPSuccess)
    json = JSON.parse(res.body)
    if json['results'] && json['results'][0] && json['results'][0]['place_id']
      return json['results'][0]['place_id']
    end
  end
  nil
end

begin
  doc = Nokogiri::XML(
    URI.open("https://www.google.com/maps/d/kml?forcekml=1&mid=#{mid}")
  )
rescue StandardError => e
  puts "- Error: Cannot read mid: #{mid}"
  puts "- Reason: #{e.message}"
  exit
end

api_key = ENV['GOOGLE_MAPS_API_KEY']
api_key_restricted = ENV['GOOGLE_MAPS_API_KEY_RESTRICTED']
title = doc.css('Document').at_css('name').children.text

# Extract style information for icons
styles = {}

# First, extract Style definitions
doc.css('Style').each do |style|
  style_id = style['id']
  if style_id && style_id.include?('normal')
    icon_style = style.at_css('IconStyle')
    if icon_style
      icon_url = icon_style.at_css('Icon href')&.text
      kml_color = icon_style.at_css('color')&.text

      # Convert KML ABGR color to RGB hex
      rgb_color = if kml_color && kml_color.length == 8
        # KML format: AABBGGRR -> #RRGGBB
        r = kml_color[6,2]
        g = kml_color[4,2]
        b = kml_color[2,2]
        "##{r}#{g}#{b}".upcase
      else
        nil
      end

      # Extract icon number from style ID (e.g., "icon-1504-0288D1-normal" -> "1504")
      icon_number = style_id[/icon-(\d+)/, 1]

      styles[style_id] = {
        icon_url: icon_url,
        kml_color: kml_color,
        rgb_color: rgb_color,
        icon_number: icon_number
      }
    end
  end
end

# Then, map StyleMaps to their normal styles
doc.css('StyleMap').each do |style_map|
  style_map_id = style_map['id']
  normal_style_url = style_map.css('Pair').find { |pair|
    pair.at_css('key')&.text == 'normal'
  }&.at_css('styleUrl')&.text&.gsub('#', '')

  if style_map_id && normal_style_url && styles[normal_style_url]
    styles[style_map_id] = styles[normal_style_url]
  end
end

lists = ''
options = %(
              <option value="" data-color="#d3a" data-custom-properties='{"iconUrl":"bootstrap-icon"}'>Current Location</option>
)

doc.css('Folder').each_with_index do |folder, index|
  lists += %(
        <li class="nav-item">
          <a class="nav-link active" href="#" data-group="#{index}">
            #{folder.at_css('name').children.text}
          </a>
        </li>
  )

  folder.css('Placemark').each do |placemark|
    name = placemark.at_css('name').children.text
    description_text = placemark.at_css('description')&.text || ''
    # Extract Place ID in any of these forms: PLACEID: ChIJ..., Place ID: ChIJ..., PlaceID: ChIJ..., etc.
    place_id = description_text[/place[\s_-]*id[:：]?\s*([A-Za-z0-9_-]+)/i, 1]

    # Get style information
    style_url = placemark.at_css('styleUrl')&.text&.gsub('#', '')
    style_info = styles[style_url] || {}

    # Use RGB color from KML, fallback to extracting from styleUrl
    color = style_info[:rgb_color] || (style_url ? "##{style_url.split('-')[2]}" : 'default')
    icon_number = style_info[:icon_number]

    coordinates = placemark.at_css('coordinates').children.text.strip.split(',')
    # If no place_id, try to fetch from Google Places API
    if !place_id || place_id.empty?
      place_id = fetch_place_id(name, coordinates[1], coordinates[0], api_key)
    end
    # Create visual color indicator for the option text
    display_name = name

    # Use Google Maps individual icon URLs with color highlight
    # Icon names mapping
    icon_names = {
      '1504' => '1504-airport-plane_4x.png',
      '1534' => '1534-cafe-cup_4x.png',
      '1577' => '1577-food-fork-knife_4x.png',
      '1598' => '1598-historic-building_4x.png',
      '1602' => '1602-hotel-bed_4x.png',
      '1684' => '1684-shopping-bag_4x.png',
      '1716' => '1716-train_4x.png',
      '1899' => '1899-blank-shape_pin_4x.png'
    }

    icon_name = icon_names[icon_number] || '1899-blank-shape_pin_4x.png'
    # Remove # from color for URL parameter
    highlight_color = color ? color.gsub('#', '') : '000000'

    # Icon 1899 uses pin-container instead of regular container
    container = (icon_number == '1899') ? 'SHARED-mymaps-pin-container_4x.png' : 'SHARED-mymaps-container_4x.png'

    # Google Maps icon URL with container and highlight
    google_icon_url = "https://mt.google.com/vt/icon/name=icons/onion/#{container},icons/onion/#{icon_name}&highlight=#{highlight_color},ff000000&scale=1.0"

    options += %(
              <option value='#{coordinates[1]},#{coordinates[0]}'
                      data-group='#{index}'
                      data-color='#{color}'
                      data-icon-url='#{google_icon_url}'
                      data-icon-number='#{icon_number}'
                      data-placeid='#{place_id}'
                      data-custom-properties='{"iconUrl":"#{google_icon_url}","iconNumber":"#{icon_number}","color":"#{color}"}'>
                #{display_name}
              </option>
    )
  end
end

html = <<~HTML
  <!DOCTYPE html>
  <html lang="en">
    <head>
      <title>#{title}</title>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">

      <script src="https://code.jquery.com/jquery-3.7.1.min.js" crossorigin="anonymous"></script>

      <!-- Bootstrap 5 CSS -->
      <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet" crossorigin="anonymous">
      <!-- Bootstrap 5 JS -->
      <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js" crossorigin="anonymous"></script>

      <!-- Choices.js CSS -->
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/choices.js/public/assets/styles/choices.min.css" />
      <!-- Choices.js JS -->
      <script src="https://cdn.jsdelivr.net/npm/choices.js/public/assets/scripts/choices.min.js"></script>

      <!-- Latest Google Maps JS API with callback -->
      <script src="https://maps.googleapis.com/maps/api/js?key=#{api_key_restricted}&callback=initMap&libraries=places,marker&loading=async" async defer></script>

      <style>
        .nav-pills { margin: 20px 0; }
        .nav-pills > li > a { padding: 5px 10px; }
        .btn { margin: 5px 0; }
        .logo-label { font-size: 12px; font-weight: bold; padding: 2px 0; width: 88px; min-width: 88px; text-align: center; color: #fff; background-color: #333; border-radius: 3px; display: inline-block; }
        .form-label { font-size: 14px; font-weight: bold; padding: 10px 0 0 15px; }
        .glyphicon-map-marker { color: #333; }
        .glyphicon-arrow-right { color: #999; }
        a:link, a:visited, a:visited:hover, a:hover, a:active { text-decoration: none; }
        #map { width: 100%; height: 300px; }
        .poi-icon { width: 16px; height: 16px; margin-right: 5px; vertical-align: middle; }
        .option-with-icon { display: flex; align-items: center; }
        .color-indicator {
          display: inline-block;
          width: 12px;
          height: 12px;
          border-radius: 50%;
          margin-right: 8px;
          border: 1px solid #ccc;
          vertical-align: middle;
        }

        /* Choices.js Bootstrap 5 theming */
        .choices {
          margin-bottom: 0;
        }
        .choices__inner {
          background-color: #fff;
          border: 1px solid #dee2e6;
          border-radius: 0.375rem;
          font-size: 1rem;
          min-height: 38px;
          padding: 0.375rem 0.75rem;
        }
        .choices__inner:focus-within {
          border-color: #86b7fe;
          outline: 0;
          box-shadow: 0 0 0 0.25rem rgba(13, 110, 253, 0.25);
        }
        .choices__list--dropdown {
          border: 1px solid #dee2e6;
          border-radius: 0.375rem;
          box-shadow: 0 0.5rem 1rem rgba(0, 0, 0, 0.15);
        }
        .choices__list--dropdown .choices__item--selectable {
          padding: 0.5rem 1rem;
        }
        .choices__list--dropdown .choices__item--selectable.is-highlighted {
          background-color: #0d6efd !important;
          color: #fff !important;
        }
        .choices[data-type*=select-one] .choices__inner {
          padding-bottom: 0.375rem;
        }

        /* Custom icon display in Choices.js using Google Maps individual icons */
        .choices__item--choice .poi-icon,
        .choices__item .poi-icon {
          display: inline-block;
          width: 20px;
          height: 20px;
          margin-right: 8px;
          vertical-align: middle;
        }

        /* Bootstrap icon styling for Current Location */
        .poi-icon-bootstrap {
          display: inline-block;
          width: 20px;
          margin-right: 8px;
          font-size: 16px;
          color: #6c757d;
          text-align: center;
          line-height: 1;
          vertical-align: text-bottom;
        }

        @media screen and (max-width: 576px) {
          .form-label { font-size: 12px; font-weight: bold; padding: 8px 0 0 15px; }
          .form-control { margin-left: 10px; width: 95%; }
        }
      </style>
    </head>

    <body>
      <div class="container my-4">
        <h4>
          <a href="https://www.google.com/maps/d/viewer?mid=#{mid}&hl=en&usp=sharing" target="_blank">#{title}</a>
        </h4>

        <ul class="nav nav-pills nav-fill mb-3 gap-2" id="groupTabs" role="tablist">
          #{lists}
        </ul>

        <form>
          <div class="row mb-3 align-items-center">
            <label class="col-sm-1 col-form-label" for="from">From:</label>
            <div class="col-sm-11">
              <select id="from" class="form-select">
                #{options}
              </select>
            </div>
          </div>

          <div class="row mb-3 align-items-center">
            <label class="col-sm-1 col-form-label" for="to">To:</label>
            <div class="col-sm-11">
              <select id="to" class="form-select">
                #{options}
              </select>
            </div>
          </div>

          <div class="row mb-3">
            <div class="col-sm-11 offset-sm-1">
              <div class="form-check form-check-inline">
                <input class="form-check-input" type="radio" name="mode" id="mode1" value="1" checked>
                <label class="form-check-label" for="mode1">Transit</label>
              </div>
              <div class="form-check form-check-inline">
                <input class="form-check-input" type="radio" name="mode" id="mode2" value="2">
                <label class="form-check-label" for="mode2">Driving</label>
              </div>
              <div class="form-check form-check-inline">
                <input class="form-check-input" type="radio" name="mode" id="mode3" value="3">
                <label class="form-check-label" for="mode3">Walking</label>
              </div>
            </div>
          </div>

          <div class="row mb-3">
            <div class="col-sm-12">
              <button class="btn btn-primary w-100" type="button" id="route">Route</button>
            </div>
          </div>
        </form>

        <div class="card mb-3">
          <div class="card-header">
            <span class="bi bi-crosshair"></span> Map Directions
          </div>
          <div class="card-body">
            <div><span class="logo-label me-2"><i class="bi bi-apple"></i> Apple</span><span id="apple">No Route Yet</span></div>
            <div><span class="logo-label me-2"><i class="bi bi-google"></i> Google</span><span id="google">No Route Yet</span></div>
          </div>
        </div>

        <div class="card">
          <div class="card-header">
            <span class="bi bi-exclamation-circle"></span> Place Info
          </div>
          <div class="card-body">
            <div id="map"></div>
          </div>
        </div>
      </div>

      <script>
        var from_html = $('#from').html();
        var to_html = $('#to').html();
        var map, marker, infowindow;
        var fromChoices, toChoices;

        function initMap() {
          // Get the first POI coordinates for map center, fallback to Tokyo
          var initialCenter = {lat: 35.6895, lng: 139.6917}; // Tokyo default
          var firstPOI = $('#from option[value!=""]').first();

          if (firstPOI.length > 0) {
            var coords = firstPOI.val().split(',');
            if (coords.length === 2 && coords[0] && coords[1]) {
              initialCenter = {
                lat: parseFloat(coords[0]),
                lng: parseFloat(coords[1])
              };
            }
          }

          map = new google.maps.Map(document.getElementById('map'), {
            center: initialCenter,
            zoom: 10,
            mapId: 'DEMO_MAP_ID' // Required for AdvancedMarkerElement
          });
          infowindow = new google.maps.InfoWindow();
        }

        // Get unique storage key for this page
        function getStorageKey() {
          return 'navSelections_' + '#{mid}';
        }

        // Load saved nav selections on page load
        function loadSavedSelections() {
          var savedSelections = localStorage.getItem(getStorageKey());
          if (savedSelections) {
            var selections = JSON.parse(savedSelections);
            $('.nav-link').removeClass('active');
            selections.forEach(function(group) {
              $(`[data-group="${group}"]`).addClass('active');
            });
            updateOptionsDisplay();
          }
        }

        // Save current nav selections
        function saveSelections() {
          var activeGroups = [];
          $('.nav-link.active').each(function() {
            activeGroups.push($(this).data('group'));
          });
          localStorage.setItem(getStorageKey(), JSON.stringify(activeGroups));
        }

        // Initialize Choices.js with custom template for icons
        function initChoices() {
          // Destroy existing instances if they exist
          if (fromChoices) fromChoices.destroy();
          if (toChoices) toChoices.destroy();

          fromChoices = new Choices('#from', {
            searchEnabled: false,
            itemSelectText: '',
            shouldSort: false,
            callbackOnCreateTemplates: function(template) {
              return {
                item: ({ classNames }, data) => {
                  const iconUrl = data.customProperties?.iconUrl || '';
                  const iconHtml = iconUrl === 'bootstrap-icon'
                    ? '<i class="bi bi-geo-alt-fill poi-icon-bootstrap"></i>'
                    : (iconUrl ? `<img src="${iconUrl}" class="poi-icon" alt="" />` : '');
                  return template(`
                    <div class="${classNames.item} ${data.highlighted ? classNames.highlightedState : classNames.itemSelectable}" data-item data-id="${data.id}" data-value="${data.value}" ${data.active ? 'aria-selected="true"' : ''} ${data.disabled ? 'aria-disabled="true"' : ''}>
                      ${iconHtml}
                      ${data.label}
                    </div>
                  `);
                },
                choice: ({ classNames }, data) => {
                  const iconUrl = data.customProperties?.iconUrl || '';
                  const iconHtml = iconUrl === 'bootstrap-icon'
                    ? '<i class="bi bi-geo-alt-fill poi-icon-bootstrap"></i>'
                    : (iconUrl ? `<img src="${iconUrl}" class="poi-icon" alt="" />` : '');
                  return template(`
                    <div class="${classNames.item} ${classNames.itemChoice} ${data.disabled ? classNames.itemDisabled : classNames.itemSelectable}" data-select-text="${this.config.itemSelectText}" data-choice ${data.disabled ? 'data-choice-disabled aria-disabled="true"' : 'data-choice-selectable'} data-id="${data.id}" data-value="${data.value}" ${data.groupId > 0 ? 'role="treeitem"' : 'role="option"'}>
                      ${iconHtml}
                      ${data.label}
                    </div>
                  `);
                }
              };
            }
          });

          toChoices = new Choices('#to', {
            searchEnabled: false,
            itemSelectText: '',
            shouldSort: false,
            callbackOnCreateTemplates: function(template) {
              return {
                item: ({ classNames }, data) => {
                  const iconUrl = data.customProperties?.iconUrl || '';
                  const iconHtml = iconUrl === 'bootstrap-icon'
                    ? '<i class="bi bi-geo-alt-fill poi-icon-bootstrap"></i>'
                    : (iconUrl ? `<img src="${iconUrl}" class="poi-icon" alt="" />` : '');
                  return template(`
                    <div class="${classNames.item} ${data.highlighted ? classNames.highlightedState : classNames.itemSelectable}" data-item data-id="${data.id}" data-value="${data.value}" ${data.active ? 'aria-selected="true"' : ''} ${data.disabled ? 'aria-disabled="true"' : ''}>
                      ${iconHtml}
                      ${data.label}
                    </div>
                  `);
                },
                choice: ({ classNames }, data) => {
                  const iconUrl = data.customProperties?.iconUrl || '';
                  const iconHtml = iconUrl === 'bootstrap-icon'
                    ? '<i class="bi bi-geo-alt-fill poi-icon-bootstrap"></i>'
                    : (iconUrl ? `<img src="${iconUrl}" class="poi-icon" alt="" />` : '');
                  return template(`
                    <div class="${classNames.item} ${classNames.itemChoice} ${data.disabled ? classNames.itemDisabled : classNames.itemSelectable}" data-select-text="${this.config.itemSelectText}" data-choice ${data.disabled ? 'data-choice-disabled aria-disabled="true"' : 'data-choice-selectable'} data-id="${data.id}" data-value="${data.value}" ${data.groupId > 0 ? 'role="treeitem"' : 'role="option"'}>
                      ${iconHtml}
                      ${data.label}
                    </div>
                  `);
                }
              };
            }
          });
        }

        // Update the dropdowns based on active selections
        function updateOptionsDisplay() {
          $('#from').html(from_html);
          $('#to').html(to_html);
          $('.nav-link:not(.active)').each(function () {
            var hide_group = $(this).data('group');
            $(`option[data-group="${hide_group}"]`).remove();
          });

          // Re-initialize Choices.js with updated options
          initChoices();

          // Trigger change event on from dropdown
          $('#from').trigger('change');
        }

        // Create a simple colored marker element
        function createColoredMarkerElement(color, iconNumber, iconUrl) {
          if (!color || color === 'default') {
            return null; // Use default marker
          }

          const markerElement = document.createElement('div');
          markerElement.style.cursor = 'pointer';
          markerElement.style.display = 'flex';
          markerElement.style.alignItems = 'center';
          markerElement.style.justifyContent = 'center';

          // Bootstrap icon marker with KML color
          markerElement.innerHTML = `
            <i class="bi bi-pin-map-fill" style="
              font-size: 32px;
              color: ${color};
              text-shadow: 1px 1px 2px rgba(0,0,0,0.5), -1px -1px 2px rgba(255,255,255,0.8);
              filter: drop-shadow(0 2px 4px rgba(0,0,0,0.3));
            "></i>
          `;

          return markerElement;
        }

        function showPlaceOnMap(lat, lng, place_name, place_id, color, icon_number, icon_url) {
          if (!map) return;
          var position = {lat: Number(lat), lng: Number(lng)};
          map.setCenter(position);
          map.setZoom(19);
          if (marker) {
            marker.map = null; // Remove previous marker
            marker = null;
          }

          // Create custom marker element
          var markerContent = createColoredMarkerElement(color, icon_number, icon_url);

          // Create AdvancedMarkerElement
          marker = new google.maps.marker.AdvancedMarkerElement({
            map: map,
            position: position,
            content: markerContent
          });

          if (place_id) {
            // Use new Places API
            const place = new google.maps.places.Place({
              id: place_id,
              requestedLanguage: 'en'
            });

            // Fetch place details using the new API
            place.fetchFields({
              fields: ['displayName', 'rating', 'googleMapsURI', 'websiteURI']
            }).then(() => {
              marker.addListener('click', function() {
                infowindow.setContent(`
                  <div>
                    <strong>${place_name}</strong><br />
                    Rating: <strong>${place.rating || 'N/A'}</strong><br />
                    <a href="${place.googleMapsURI || '#'}" target="_blank">View on Google Maps</a>
                    ${place.websiteURI ? `<br /><a href="${place.websiteURI}" target="_blank">Website</a>` : ''}
                  </div>
                `);
                infowindow.open({
                  anchor: marker,
                  map: map
                });
              });
            }).catch((error) => {
              console.log('Error fetching place details:', error);
              // Fallback to basic info without place details
              marker.addListener('click', function() {
                infowindow.setContent(`
                  <div>
                    <strong>${place_name}</strong><br />
                    <a href="https://www.google.com/maps/place/?q=place_id:${place_id}" target="_blank">View on Google Maps</a>
                  </div>
                `);
                infowindow.open({
                  anchor: marker,
                  map: map
                });
              });
            });
          }
        }

        $('.nav-pills .nav-link').on('click', function (event) {
          event.preventDefault();
          var group = $(this).data('group');
          $(this).toggleClass('active');

          saveSelections();
          updateOptionsDisplay();
        });

        // Handle change events for Choices.js dropdowns
        $(document).on('change', '#from, #to', function () {
          $('#apple').empty().append('No Route Yet');
          $('#google').empty().append('No Route Yet');
        });

        $('[name="mode"]').on('click', function () {
          $('#apple').empty().append('No Route Yet');
          $('#google').empty().append('No Route Yet');
        });

        $('#route').on('click', function () {
          var from_value = $('#from').val();
          var from_text = $('#from option:selected').text();
          var from_color = $('#from option:selected').data('color');
          var to_value = $('#to').val();
          var to_text = $('#to option:selected').text();
          var to_color = $('#to option:selected').data('color');
          var mode = $('[name="mode"]:checked').val();
          var href_text = `
            <span class="bi bi-geo-alt-fill" style="color: ${from_color};"></span>
            <span style='color: ${from_color};'>${from_text}</span>
            &nbsp;<span class="bi bi-arrow-right"></span>&nbsp;
            <span class="bi bi-geo-alt-fill" style="color: ${to_color};"></span>
            <span style='color: ${to_color};'>${to_text}</span>
          `;

          var mode_apple = 'r';
          var mode_google = 'transit';

          if (mode == 2) { mode_apple = 'd'; mode_google = 'driving'; }
          else if (mode == 3) { mode_apple = 'w'; mode_google = 'walking'; }

          var api_apple = `http://maps.apple.com/?saddr=${from_value}&daddr=${to_value}&dirflg=${mode_apple}`;
          var api_google = `https://www.google.com/maps/dir/?api=1&origin=${from_value}&destination=${to_value}&travelmode=${mode_google}`;

          $('#apple').empty().append(`<a href="${api_apple}" target="_blank">${href_text}</a>`);
          $('#google').empty().append(`<a href="${api_google}" target="_blank">${href_text}</a>`);
        });

        // Use event delegation for the change event since Choices.js recreates the select
        $(document).on('change', '#from', function () {
          var location = $(this).val();
          var geocode = location.split(',');
          var place_name = $(this).find('option:selected').text();
          var place_id = $(this).find('option:selected').data('placeid') || '';
          var color = $(this).find('option:selected').data('color') || '';
          var icon_number = $(this).find('option:selected').data('icon-number') || '';
          var icon_url = $(this).find('option:selected').data('icon-url') || '';
          if (geocode.length == 2 && geocode[0] && geocode[1]) {
            showPlaceOnMap(geocode[0], geocode[1], place_name, place_id, color, icon_number, icon_url);
          } else {
            if (marker) {
              marker.map = null;
              marker = null;
            }
          }
        });

        // Load saved selections when page is ready
        $(document).ready(function() {
          loadSavedSelections();
          // Initialize Choices.js after loading saved selections
          initChoices();
        });
      </script>
      <!-- Bootstrap Icons -->
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    </body>
  </html>
HTML

File.write("#{file}.html", html)
