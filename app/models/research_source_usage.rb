class ResearchSourceUsage < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :connection, class_name: "EquiblesConnection", optional: true
end
