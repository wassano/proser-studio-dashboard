Rails.application.routes.draw do
  get "/up", to: "health#show"
  get "/auth/google", to: "sessions#start"
  get "/auth/callback", to: "sessions#callback"
  get "/auth/failure", to: "sessions#failure"
  get "/api/session", to: "sessions#show"
  delete "/api/session", to: "sessions#destroy"
  namespace :api do
    namespace :admin do
      resource :settings, only: %i[show update]
      resources :plans, only: %i[index create update]
      resources :licenses, only: %i[index create update]
      resources :installations, only: %i[index update] do
        post :approve, on: :member
      end
      resources :releases, only: %i[index create] do
        post :upload, on: :member
        post :publish, on: :member
        post :withdraw, on: :member
      end
      resources :releases, only: [] do
        resources :uploads, controller: "release_uploads", only: %i[create update destroy] do
          post :complete, on: :member
        end
      end
      get "/audit", to: "audit#index"
    end
    namespace :ci do
      resources :releases, only: :create do
        post :complete, on: :member
        resources :uploads, controller: "release_uploads", only: %i[create update destroy] do
          post :complete, on: :member
        end
      end
    end
    namespace :v1 do
      get "/releases", to: "releases#index"
      get "/releases/:release_id/files/:id/:filename", to: "releases#download", constraints: { filename: /[^\/]+/ }, format: false
      post "/installations/register", to: "devices#register"
      post "/installations/heartbeat", to: "devices#heartbeat"
      post "/installations/update", to: "devices#update_check"
      get "/updates/:release_id/:metadata", to: "updates#metadata", constraints: { metadata: /latest(?:-mac)?\.yml/ }, format: false
      get "/updates/:release_id/files/:id/:filename", to: "updates#download", constraints: { filename: /[^\/]+/ }, format: false
    end
  end
  get "/downloads", to: "dashboard#index"
  root "dashboard#index"
end
