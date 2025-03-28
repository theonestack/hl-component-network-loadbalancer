CloudFormation do

  default_tags = []
  default_tags << { Key: "Environment", Value: Ref("EnvironmentName") }
  default_tags << { Key: "EnvironmentType", Value: Ref("EnvironmentType") }

  tags = external_parameters.fetch(:tags, [])
  tags.each do |key, value|
    default_tags << { Key: key, Value: value }
  end if defined? tags

  loadbalancer_scheme = external_parameters[:loadbalancer_scheme]
  static_ips = external_parameters[:static_ips]
  maximum_availability_zones = external_parameters[:maximum_availability_zones]
  loadbalancer_attributes = external_parameters[:loadbalancer_attributes]
  private = loadbalancer_scheme == 'internal' ? true : false

  if !private && static_ips
    Condition(:StaticIPs, FnNot(FnEquals(Ref(:Nlb0EIPAllocationId), "")))
  end
  
  Condition(:AddSecurityGroups, FnNot(FnEquals(FnJoin(',', Ref(:SecurityGroupIds)), '')))

  ElasticLoadBalancingV2_LoadBalancer(:NetworkLoadBalancer) do
    Type 'network'

    if !private && static_ips
      SubnetMappings(
        FnIf(:StaticIPs,
          maximum_availability_zones.times.collect {|az| {SubnetId: FnSelect(az, Ref('SubnetIds')), AllocationId: Ref("Nlb#{az}EIPAllocationId")}},
          Ref('AWS::NoValue')
        )
      )
    else
      Scheme 'internal' if private
      Subnets Ref('SubnetIds')
    end

    SecurityGroups(
      FnIf(:AddSecurityGroups, Ref('SecurityGroupIds'), Ref('AWS::NoValue'))
    )
    
    Tags default_tags
    unless loadbalancer_attributes.nil?
      LoadBalancerAttributes loadbalancer_attributes.map {|key,value| { Key: key, Value: value } }
    end
  end
  
  
  targetgroups = external_parameters.fetch(:targetgroups, {})
  targetgroups.each do |tg_name, params|

    ElasticLoadBalancingV2_TargetGroup("#{tg_name}TargetGroup") {
      VpcId Ref(:VPCId)
      Protocol params.has_key?('protocol') ? params['protocol'] : 'TCP'
      Port params['port']

      TargetType params['type'] if params.has_key?('type')

      if params.has_key?('type') and params['type'] == 'ip' and params.has_key? 'target_ips'
        Targets (params['target_ips'].map {|ip|  { 'Id' => ip['ip'], 'Port' => ip['port'], 'AvailabilityZone' => ip['az']? ip['az'] : nil }.compact})
      end

      if params.has_key?('attributes')
        TargetGroupAttributes params['attributes'].map { |key,value| { Key: key, Value: value } }
      end

      if params.has_key?('healthcheck')
        HealthCheckPort params['healthcheck']['port'] if params['healthcheck'].has_key?('port')
        HealthCheckProtocol params['healthcheck'].has_key?('protocol') ? params['healthcheck']['protocol'] : 'TCP'
        HealthCheckPath params['healthcheck']['path'] if params['healthcheck'].has_key?('path')
        HealthCheckIntervalSeconds params['healthcheck']['interval'] if params['healthcheck'].has_key?('interval')
        HealthCheckTimeoutSeconds params['healthcheck']['timeout'] if params['healthcheck'].has_key?('timeout')
        HealthyThresholdCount params['healthcheck']['heathy_count'] if params['healthcheck'].has_key?('heathy_count')
        UnhealthyThresholdCount params['healthcheck']['unheathy_count'] if params['healthcheck'].has_key?('unheathy_count')
        Matcher ({ HttpCode: params['healthcheck']['code'] }) if params ['healthcheck'].has_key?('code')
      end

      Tags default_tags
    }
    
    Output("#{tg_name}TargetGroup") {
      Value(Ref("#{tg_name}TargetGroup"))
      Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{tg_name}TargetGroup")
    }
    
  end

  listeners = external_parameters.fetch(:listeners, {})
  listeners.each do |listener_name, params|

    ElasticLoadBalancingV2_Listener("#{listener_name}Listener") {
      Protocol params['protocol'].upcase
      Port params['port']
      LoadBalancerArn Ref(:NetworkLoadBalancer)

      if params['protocol'].upcase == 'TLS'
        Certificates [{ CertificateArn: Ref('SslCertId') }]
        SslPolicy params['ssl_policy'] if params.has_key?('ssl_policy')
      end

      DefaultActions ([
          TargetGroupArn: Ref("#{params['targetgroup']}TargetGroup"),
          Type: "forward"
      ])
    }

    if (params.has_key?('certificates')) && (params['protocol'].upcase == 'TLS') && (params['certificates'].any?)
      ElasticLoadBalancingV2_ListenerCertificate("#{listener_name}ListenerCertificate") {
        Certificates params['certificates'].map { |certificate| { CertificateArn: FnSub("${#{certificate}}") }  }
        ListenerArn Ref("#{listener_name}Listener")
      }
    end
    
    Output("#{listener_name}Listener") {
      Value(Ref("#{listener_name}Listener"))
      Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{listener_name}Listener")
    }

  end


  dns_format = external_parameters[:dns_format]
  records = external_parameters.fetch(:records, [])
  records.each do |record|
    name = (['apex',''].include? record) ? dns_format : "#{record}.#{dns_format}."
    Route53_RecordSet("#{record.gsub('*','Wildcard').gsub('.','Dot').gsub('-','')}LoadBalancerRecord") do
      HostedZoneName FnSub("#{dns_format}.")
      Name FnSub(name)
      Type 'A'
      AliasTarget ({
          DNSName: FnGetAtt(:NetworkLoadBalancer, :DNSName),
          HostedZoneId: FnGetAtt(:NetworkLoadBalancer, :CanonicalHostedZoneID)
      })
    end

  end

  Output(:LoadBalancer) {
    Value(Ref(:NetworkLoadBalancer))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-LoadBalancer")
  }

  Output(:LoadBalancerDNSName) {
    Value(FnGetAtt(:NetworkLoadBalancer, :DNSName))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-DNSName")
  }

  Output(:LoadBalancerCanonicalHostedZoneID) {
    Value(FnGetAtt(:NetworkLoadBalancer, :CanonicalHostedZoneID))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-CanonicalHostedZoneID")
  }
  
end
