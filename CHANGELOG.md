## 1.0.4 (October 3, 2025)

BUG FIXES:
* resource/fortiappseccloud_waf_app: Prevent panic (`interface{} is nil, not []interface{}`) when IPRegion API response no longer includes `region` and instead returns `support_platform_regions`.

ENHANCEMENTS:
* resource/fortiappseccloud_waf_app: Extract platform from current API field `cluster:platform` instead of deprecated `region`.

## 1.0.3 (December 9, 2024)

BUG FIXES:

* **Guides:** Fix migration document path from Guides to guides.

## 1.0.2 (December 8, 2024)

IMPROVEMENTS:

* **Guides:** Added document for FortiWebCloud migration.


## 1.0.1 (December 8, 2024)

IMPROVEMENTS:

* **openapi_validation:** Added document in `waf_openapi_validation.html.markdown`


## 1.0.0

FEATURES:

* **New Resource:** `FrotiAppSec Cloud`