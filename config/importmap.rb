# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "bootstrap", to: "bootstrap.bundle.min.js"
pin "keepalive"
pin "polling"
pin "copy_button"
pin "passkeys"
pin "chart.js" # @4.5.1, jsDelivr +esm build (self-contained) with its @kurkle/color import pointed at the pin below
pin "@kurkle/color", to: "@kurkle--color.js" # @0.3.4
