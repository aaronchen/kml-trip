# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a KML to HTML converter tool that transforms Google My Maps KML data into interactive web pages for trip planning. The generated HTML pages allow users to route between points of interest using Apple Maps or Google Maps.

## Technology Stack

- **Ruby 3.4.2** - Main scripting language
- **Google Maps APIs** - For place data and mapping
- **Bootstrap 5** - Frontend styling
- **jQuery** - JavaScript functionality

## Key Commands

### Generate HTML from KML
```bash
ruby kml_to_html.rb <mid> <output_filename>
```

- `<mid>`: Google My Maps ID (from the sharing URL)
- `<output_filename>`: Name for the generated HTML file (without .html extension)

Example:
```bash
ruby kml_to_html.rb 12qPGjgW4a7xRZDtdBUCrNkcBK5-46YP8 tokyo-trip
```

### Environment Setup

Ensure you have a `.env` file with Google Maps API keys:
```
GOOGLE_MAPS_API_KEY=your_full_access_key
GOOGLE_MAPS_API_KEY_RESTRICTED=your_restricted_key
```

### Dependencies

The script requires these Ruby gems:
- `nokogiri` - XML/HTML parsing
- `dotenv` - Environment variable loading

Install with:
```bash
gem install nokogiri dotenv
```

## Architecture

### Core Script (`kml_to_html.rb`)

The main Ruby script follows this flow:
1. Downloads KML data from Google My Maps using the provided mid
2. Parses POI locations, names, and descriptions
3. Attempts to fetch Google Place IDs for enhanced place information
4. Generates a complete HTML page with embedded JavaScript
5. Outputs the HTML file for direct hosting

### Generated HTML Structure

Each generated HTML file contains:
- **Navigation tabs** - Filter POIs by categories (folders from KML)
- **Route planner** - From/To dropdowns with all POIs
- **Travel mode selector** - Transit, driving, or walking
- **Map integration** - Google Maps with place details
- **External routing** - Links to Apple Maps and Google Maps

### Place ID Enhancement

The script can extract Place IDs from POI descriptions in formats like:
- `PLACEID: ChIJ...`
- `Place ID: ChIJ...` 
- `PlaceID: ChIJ...`

If no Place ID is found, it automatically queries the Google Places API to find one based on location and name.

## File Organization

- `kml_to_html.rb` - Main conversion script
- `*.html` - Generated trip pages (e.g., `tokyo-2025.html`, `nagoya-2024.html`)
- `index.html` - Main landing page
- `images/` - Icon assets for different POI categories
- `.env` - API keys (not committed to git)
- `.ruby-version` - Ruby version specification

## Development Notes

- The script fetches KML data directly from Google My Maps public URLs
- Generated HTML is self-contained with inline CSS and JavaScript
- Bootstrap 5 and jQuery are loaded from CDN
- All POI data is embedded directly in the HTML for offline functionality
- Color coding matches the original Google My Maps categories