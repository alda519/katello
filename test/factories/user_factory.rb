FactoryGirl.define do
  factory :user do
    sequence(:username) { |n| "user#{n}" }
    sequence(:email) { |n| "user#{n}@katello.org" }
    password "password1"
    sequence(:remote_id) { |n| "remote#{n}" }

    trait :batman do
      username  "batman"
      password  "ihaveaterriblepassword"
      email     "batman@wayne.ent.com"
      remote_id "batman"
    end

  end
end
