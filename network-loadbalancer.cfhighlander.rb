CfhighlanderTemplate do
  Name 'network-loadbalancer'
  Description "network-loadbalancer - #{component_version}"

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','production'], isGlobal: true
    ComponentParam 'DnsDomain'
    ComponentParam 'SslCertId', ''

    maximum_availability_zones.times do |az|
      if loadbalancer_scheme != 'internal' && static_ips
        ComponentParam "Nlb#{az}EIPAllocationId", ""
      end
    end

    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
    ComponentParam 'SecurityGroupIds', type: 'CommaDelimitedList'
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'

  end

end
