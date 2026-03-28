Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "events#index"

  get "schedule", to: "events#index", as: :schedule
  get "archive", to: "events#archive", as: :archive

  resources :events, only: [ :index, :show ], param: :slug do
    member do
      post :status
    end
  end

  resources :teams, only: [ :index, :show ], param: :slug

  post "sessions/keepalive", to: "sessions/keepalive#create"

  # Internal admin routes
  namespace :internal do
    root "home#index"
    mount Sidekiq::Web => "/sidekiq"

    resources :reports, only: [ :index ]
    resources :teams
    resources :events do
      collection do
        get :archive
      end
      member do
        post :go_live
        post :end_event
        post :mark_replay_pending
        post :mark_technical_difficulties
        post :publish_replay
      end
    end

    resources :uploads, only: [:index] do
      collection do
        post :create_upload_url
      end
    end
  end
end
