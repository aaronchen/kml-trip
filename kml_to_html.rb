#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'open-uri'
require 'json'
require 'net/http'

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

api_key = 'AIzaSyCt6MJCC4v14LEdhjDFwseIjDJGt45MUfI'
title = doc.css('Document').at_css('name').children.text
lists = ''
options = %(
              <option value="" data-color="#d3a">Current Location</option>
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
    color = placemark.at_css('styleUrl').children.text.split('-')[2]
    coordinates = placemark.at_css('coordinates').children.text.strip.split(',')
    # If no place_id, try to fetch from Google Places API
    if !place_id || place_id.empty?
      place_id = fetch_place_id(name, coordinates[1], coordinates[0], api_key)
    end
    options += %(
              <option value='#{coordinates[1]},#{coordinates[0]}'
                      data-group='#{index}'
                      data-color='#{color}'
                      data-placeid='#{place_id}'>
                #{name}
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

      <!-- Latest Google Maps JS API with callback -->
      <script src="https://maps.googleapis.com/maps/api/js?key=#{api_key}&callback=initMap&libraries=places" async defer></script>

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
        var map, marker, infowindow, service;

        function initMap() {
          // Default map center
          map = new google.maps.Map(document.getElementById('map'), {
            center: {lat: 35.6895, lng: 139.6917}, // Tokyo
            zoom: 10
          });
          infowindow = new google.maps.InfoWindow();
          service = new google.maps.places.PlacesService(map);
        }

        function showPlaceOnMap(lat, lng, place_name, place_id) {
          if (!map) return;
          var position = {lat: Number(lat), lng: Number(lng)};
          map.setCenter(position);
          map.setZoom(19);
          if (marker) marker.setMap(null);
          marker = new google.maps.Marker({
            map: map,
            position: position
          });
          if (place_id) {
            service.getDetails({ placeId: place_id }, function (place, status) {
              if (status === google.maps.places.PlacesServiceStatus.OK) {
                google.maps.event.clearListeners(marker, 'click');
                google.maps.event.addListener(marker, 'click', function() {
                  infowindow.setContent(`
                    <div>
                      <strong>${place_name}</strong><br />
                      Rating: <strong>${place.rating || 'N/A'}</strong><br />
                      <a href="${place.url}" target="_blank">View on Google Maps</a>
                    </div>
                  `);
                  infowindow.open(map, marker);
                });
              }
            });
          }
        }

        $('.nav-pills .nav-link').on('click', function (event) {
          event.preventDefault();
          var group = $(this).data('group');
          $(this).toggleClass('active');

          $('#from').html(from_html).change();
          $('#to').html(to_html);
          $('.nav-link:not(.active)').each(function () {
            var hide_group = $(this).data('group');
            $(`option[data-group="${hide_group}"]`).remove();
          });
        });

        $('#from, #to, [name="mode"]').on('click', function () {
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
            <span class="bi bi-geo-alt-fill" style="color: #${from_color};"></span>
            <span style='color: #${from_color};'>${from_text}</span>
            &nbsp;<span class="bi bi-arrow-right"></span>&nbsp;
            <span class="bi bi-geo-alt-fill" style="color: #${to_color};"></span>
            <span style='color: #${to_color};'>${to_text}</span>
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

        $('#from').on('change', function () {
          var location = $(this).val();
          var geocode = location.split(',');
          var place_name = $(this).find('option:selected').text();
          var place_id = $(this).find('option:selected').data('placeid') || '';
          if (geocode.length == 2 && geocode[0] && geocode[1]) {
            showPlaceOnMap(geocode[0], geocode[1], place_name, place_id);
          } else {
            if (marker) marker.setMap(null);
          }
        });
      </script>
      <!-- Bootstrap Icons -->
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    </body>
  </html>
HTML

File.write("#{file}.html", html)
