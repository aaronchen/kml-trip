#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'open-uri'

mid = ARGV[0]
file = ARGV[1]

if !mid || !file
  puts 'Usage: kml_to_html mid file'
  exit
end

# To find Place ID for POIs, go to:
#   https://developers.google.com/places/place-id
# Later, Edit POIs and put 'PLACEID:place_id' in POI description

begin
  doc = Nokogiri::XML(
    open("http://www.google.com/maps/d/kml?forcekml=1&mid=#{mid}")
  )
rescue StandardError => e
  puts "- Error: Cannot read mid: #{mid}"
  puts "- Reason: #{e.message}"
  exit
end

api_key = 'MgAP49o33zDkwujnqgpChKn5rJGatPkiCySazIA'.reverse
title = doc.css('Document').at_css('name').children.text
lists = ''
options = %(
              <option value="" data-color="#d3a">Current Location</option>
)

doc.css('Folder').each_with_index do |folder, index|
  lists += %(
        <li class='active'>
          <a href='#' data-group='#{index}'>
            #{folder.at_css('name').children.text}
          </a>
        </li>
  )

  folder.css('Placemark').each do |placemark|
    name = placemark.at_css('name').children.text
    description = (
                    placemark.at_css('description')
                    &.children
                    &.text
                    &.split('PLACEID:') || []
                  )[1]&.gsub(/<br>.*/, '')
    color = placemark.at_css('styleUrl').children.text.split('-')[2]
    coordinates = placemark.at_css('coordinates').children.text.strip.split(',')
    options += %(
              <option value='#{coordinates[1]},#{coordinates[0]}'
                      data-group='#{index}'
                      data-color='#{color}'
                      data-placeid='#{description}'>
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

      <script src="https://code.jquery.com/jquery-3.2.1.min.js" integrity="sha256-hwg4gsxgFZhOsEEamdOYGBf13FyQuiTwlAQgxVSNgt4=" crossorigin="anonymous"></script>

      <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" integrity="sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u" crossorigin="anonymous">

      <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>

      <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootswatch/3.3.7/paper/bootstrap.min.css">

      <script src="https://maps.googleapis.com/maps/api/js?key=#{api_key}&libraries=places">
      </script>

      <style>
        .nav-pills { margin: 20px 0; }
        .nav-pills > li > a { padding: 5px 10px; }
        .btn { margin: 5px 0; }
        .label { background-color: #444; display: inline-block; margin: 10px 10px 0 0; padding: 4px 0; width: 45px; }
        .glyphicon-map-marker { color: #333; }
        .glyphicon-arrow-right { color: #999; }
        a:link, a:visited, a:visited:hover, a:hover, a:active { text-decoration: none; }
        #map { width: 100%; height: 300px; }
        @media screen and (max-width: 576px) {
          .control-label { font-size: 12px; font-weight: bold; padding: 8px 0 0 15px; }
          .form-control { margin-left: 10px; width: 95%; }
          .radio { margin-left: 10px; }
        }
      </style>
    </head>

    <body>
      <div class="container">
        <h4>
          <a href="https://www.google.com/maps/d/viewer?mid=#{mid}&hl=en&usp=sharing" target="_blank">#{title}</a>
        </h4>

        <ul class="nav nav-pills">
          #{lists}
        </ul>

        <form class="form-horizontal">
          <div class="form-group">
            <label class="col-sm-1 col-xs-1 control-label" for="from">From:</label>
            <div class="col-sm-11 col-xs-11">
              <select id="from" class="form-control">
                #{options}
              </select>
            </div>
          </div>

          <div class="form-group">
            <label class="col-sm-1 col-xs-1 control-label" for="to">To:</label>
            <div class="col-sm-11 col-xs-11">
              <select id="to" class="form-control">
                #{options}
              </select>
            </div>
          </div>

          <div class="form-group">
            <div class="col-sm-11 col-sm-offset-1 col-xs-11 col-xs-offset-1">
              <div class="radio">
                <label class="radio-inline">
                  <input type="radio" name="mode" value="1" checked> Transit
                </label>
                <label class="radio-inline">
                  <input type="radio" name="mode" value="2"> Driving
                </label>
                <label class="radio-inline">
                  <input type="radio" name="mode" value="3"> Walking
                </label>
              </div>
            </div>
          </div>

          <div class="form-group">
            <div class="col-sm-12 col-xs-12">
              <button class="btn btn-primary btn-block" type="button" id="route">Route</button>
            </div>
          </div>
        </form>

        <div class="panel panel-default">
          <div class="panel-heading">
            <h3 class="panel-title">
              <span class="glyphicon glyphicon-screenshot"></span> Map Directions
            </h3>
          </div>
          <div class="panel-body">
            <div><span class="label">Apple</span><span id="apple">No Route Yet</span></div>
            <div><span class="label">Google</span><span id="google">No Route Yet</span></div>
          </div>
        </div>

        <div class="panel panel-default">
          <div class="panel-heading">
            <h3 class="panel-title">
              <span class="glyphicon glyphicon-exclamation-sign"></span> Place Info
            </h3>
          </div>
          <div class="panel-body">
            <div id="map"></div>
          </div>
        </div>
      </div>

      <script>
        var from_html = $('#from').html();
        var to_html = $('#to').html();
        // var icon_colors = ['4E342E','0288D1','558B2F','673AB7','E65100'];

        $('.nav-pills a').on('click', function (event) {
          event.preventDefault();
          var group = $(this).data('group');
          $(this).closest('li').toggleClass('active');

          $('#from').html(from_html).change();
          $('#to').html(to_html);
          $('li:not([class^="active"])').each(function () {
            var hide_group = $(this).find('a').data('group');
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
            <span class="glyphicon glyphicon-map-marker"></span>
            <span style='color: #${from_color};'>${from_text}</span>
            &nbsp;<span class="glyphicon glyphicon-arrow-right"></span>&nbsp;
            <span class="glyphicon glyphicon-map-marker"></span>
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
          // var color = $(this).find('option:selected').data('color');
          var place_id = $(this).find('option:selected').data('placeid') || '';

          // if (icon_colors.indexOf(color) < 0) { color = 'E65100'; }

          if (geocode.length == 2) {
            var map = new google.maps.Map($('#map')[0], {
              center: {lat: Number(geocode[0]), lng: Number(geocode[1])},
              zoom: 19
            });

            if (place_id) {
              var infowindow = new google.maps.InfoWindow();
              var service = new google.maps.places.PlacesService(map);
              service.getDetails({ placeId: place_id }, function (place, status) {
                if (status == google.maps.places.PlacesServiceStatus.OK) {
                  var marker = new google.maps.Marker({
                    map: map,
                    position: place.geometry.location,
                    // icon: {
                    //   url: `images/icon-${color}.png`,
                    //   size: new google.maps.Size(35, 35),
                    //   origin: new google.maps.Point(0, 0),
                    //   anchor: new google.maps.Point(17, 34),
                    //   scaledSize: new google.maps.Size(35, 35)
                    // }
                  });
                  google.maps.event.addListener(marker, 'click', function() {
                    infowindow.setContent(`
                      <div>
                        <strong>${place_name}</strong><br />
                        Rating: <strong>${place.rating}</strong><br />
                        <a href="${place.url}" target="_blank">View on Google Maps</a>
                      </div>
                    `);
                    infowindow.open(map, this);
                  });
                }
              });
            }
          } else {
            $('#map').empty();
          }
        });
      </script>
    </body>
  </html>
HTML

File.write("#{file}.html", html)
