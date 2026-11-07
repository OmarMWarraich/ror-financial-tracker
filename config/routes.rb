Rails.application.routes.draw do
  resource :market_dashboard, only: :show, controller: "market_dashboards" do
    post :refresh
  end
  get "portfolio_demo", to: "portfolio_demos#show", as: :portfolio_demo
  get "research_demo", to: "research_demos#show", as: :research_demo
  get "configurations/ios_v1", to: "native_configurations#show", defaults: { platform: "ios", format: :json }
  get "configurations/android_v1", to: "native_configurations#show", defaults: { platform: "android", format: :json }
  resource :deposit_information, only: :show, controller: "deposit_information" do
    post :check
  end
  resources :sandbox_accounts, only: %i[index create show] do
    member { post :load_fixture }
    resources :sandbox_mandates, only: :create do
      member do
        patch :transition
        post :execute
      end
    end
  end
  resources :broker_connections, only: %i[index create destroy] do
    member do
      post :refresh
      post :request_elevation
    end
  end
  resource :equibles_evidence, only: %i[show update destroy], controller: "equibles_evidence" do
    post :refresh
  end
  resources :user_stocks, only: [:create, :destroy]
  resources :research_chats, only: %i[index create show] do
    member do
      get :snapshot
      post :stop
    end
  end
  devise_for :users, controllers: { registrations: "users/registrations", sessions: "users/sessions" }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  get 'my_portfolio', to: 'users#my_portfolio'
  get 'search_stock', to: 'stocks#search'
  get 'my_friends', to: 'users#my_friends'
  get 'search_friend', to: 'users#search'
  resources :friendships, only: [:create, :destroy]
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "welcome#index"
  resources :users, only: [:show]
end
