class ExpireEquiblesEvidenceJob < ApplicationJob
  queue_as :maintenance

  def perform
    EquiblesConnection.where.not(snapshot: {}).find_each do |connection|
      connection.with_lock do
        connection.expire_evidence!(EquiblesEntitlement.new(connection.user))
      end
    end
  end
end
