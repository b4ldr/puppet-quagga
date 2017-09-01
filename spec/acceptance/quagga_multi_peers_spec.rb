# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'quagga class multi peers' do
  router1 = find_host_with_role(:router1)
  router2 = find_host_with_role(:router2)
  router3 = find_host_with_role(:router3)
  router1_ip = fact_on(router1, 'ipaddress')
  router1_ip6 = '2001:db8:1::1'
  router1_asn = 64_496
  router2_ip = fact_on(router2, 'ipaddress')
  router2_ip6 = '2001:db8:1::2'
  router2_asn = 64_497
  router3_ip = fact_on(router3, 'ipaddress')
  router3_ip6 = '2001:db8:1::3'
  router3_asn = 64_498
  ipv6_network = '2001:db8:1::/64'
  ipv4_network = router1_ip.sub(%r{\d+$}, '0/24')
  on(router1, "ip -6 addr add #{router1_ip6}/64 dev eth0", acceptable_exit_codes: [0, 2])
  on(router2, "ip -6 addr add #{router2_ip6}/64 dev eth0", acceptable_exit_codes: [0, 2])
  on(router3, "ip -6 addr add #{router3_ip6}/64 dev eth0", acceptable_exit_codes: [0, 2])
  context 'basic' do
    pp1 = <<-EOF
    class { '::quagga': }
    class { '::quagga::bgpd':
      my_asn => #{router1_asn},
      router_id => '#{router1_ip}',
      networks4 => [ '#{ipv4_network}'],
      networks6 => [ '#{ipv6_network}'],
      peers => {
        '#{router2_asn}' => {
          'addr4' => ['#{router2_ip}'],
          'addr6' => ['#{router2_ip6}'],
          'desc'  => 'TEST Network'
          },
        '#{router3_asn}' => {
          'addr4' => ['#{router3_ip}'],
          'addr6' => ['#{router3_ip6}'],
          'desc'  => 'TEST Network'
          },
      }
    }
    EOF
    pp2 = <<-EOF
    class { '::quagga': }
    class { '::quagga::bgpd':
      my_asn => #{router2_asn},
      router_id => '#{router2_ip}',
      networks4 => [ '#{ipv4_network}'],
      networks6 => [ '#{ipv6_network}'],
      peers => {
        '#{router1_asn}' => {
          'addr4' => ['#{router1_ip}'],
          'addr6' => ['#{router1_ip6}'],
          'desc'  => 'TEST Network'
          }
      }
    }
    EOF
    pp3 = <<-EOF
    class { '::quagga': }
    class { '::quagga::bgpd':
      my_asn => #{router3_asn},
      router_id => '#{router3_ip}',
      networks4 => [ '#{ipv4_network}'],
      networks6 => [ '#{ipv6_network}'],
      peers => {
        '#{router1_asn}' => {
          'addr4' => ['#{router1_ip}'],
          'addr6' => ['#{router1_ip6}'],
          'desc'  => 'TEST Network'
          }
      }
    }
    EOF
    it 'work with no errors' do
      apply_manifest(pp1, catch_failures: true)
      apply_manifest_on(router2, pp2, catch_failures: true)
      apply_manifest_on(router3, pp3, catch_failures: true)
    end
    it 'clean puppet run' do
      expect(apply_manifest(pp1, catch_failures: true).exit_code).to eq 0
    end
    it 'r2 clean puppet run' do
      expect(apply_manifest_on(router2, pp2, catch_failures: true).exit_code).to eq 0
    end
    it 'r3 clean puppet run' do
      expect(apply_manifest_on(router3, pp3, catch_failures: true).exit_code).to eq 0
      # allow peers to configure and establish
      sleep(10)
    end
    describe command('cat /etc/quagga/bgpd.conf 2>&1') do
      its(:stdout) { is_expected.to match(%r{}) }
    end
    describe service('quagga') do
      it { is_expected.to be_running }
    end
    describe process('bgpd') do
      its(:user) { is_expected.to eq 'quagga' }
      it { is_expected.to be_running }
    end
    describe port(179) do
      it { is_expected.to be_listening }
    end
    describe command("ping -c 1 #{router2_ip}") do
      its(:exit_status) { is_expected.to eq 0 }
    end
    describe command("ping -c 1 #{router3_ip}") do
      its(:exit_status) { is_expected.to eq 0 }
    end
    describe command("ping6 -I eth0 -c 1 #{router2_ip6}") do
      its(:exit_status) { is_expected.to eq 0 }
    end
    describe command("ping6 -I eth0 -c 1 #{router3_ip6}") do
      its(:exit_status) { is_expected.to eq 0 }
    end
    describe command('vtysh -c \'show ip bgp sum\'') do
      its(:stdout) { is_expected.to match(%r{#{router2_ip}\s+4\s+#{router2_asn}}) }
      its(:stdout) { is_expected.to match(%r{#{router3_ip}\s+4\s+#{router3_asn}}) }
    end
    describe command("vtysh -c \'show ip bgp neighbors #{router2_ip}\'") do
      its(:stdout) { is_expected.to match(%r{BGP state = Established}) }
    end
    describe command("vtysh -c \'show ip bgp neighbors #{router3_ip}\'") do
      its(:stdout) { is_expected.to match(%r{BGP state = Established}) }
    end
    describe command("vtysh -c \'show ip bgp neighbors #{router2_ip} advertised-routes\'") do
      its(:stdout) { is_expected.to match(%r{#{ipv4_network}\s+#{router1_ip}\s+\d+\s+\d+\s+i}) }
    end
    describe command("vtysh -c \'show ip bgp neighbors #{router3_ip} advertised-routes\'") do
      its(:stdout) { is_expected.to match(%r{#{ipv4_network}\s+#{router1_ip}\s+\d+\s+\d+\s+i}) }
    end
    describe command('vtysh -c \'show ipv6 bgp sum\'') do
      its(:stdout) { is_expected.to match(%r{#{router2_ip6}\s+4\s+#{router2_asn}}i) }
    end
    describe command('vtysh -c \'show ipv6 bgp sum\'') do
      its(:stdout) { is_expected.to match(%r{#{router3_ip6}\s+4\s+#{router3_asn}}i) }
    end
    describe command("vtysh -c \'show ip bgp neighbors #{router2_ip6}\'") do
      its(:stdout) { is_expected.to match(%r{BGP state = Established}) }
    end
    describe command("vtysh -c \'show ip bgp neighbors #{router3_ip6}\'") do
      its(:stdout) { is_expected.to match(%r{BGP state = Established}) }
    end
    describe command("vtysh -c \'show ipv6 bgp neighbors #{router2_ip6} advertised-routes\'") do
      its(:stdout) { is_expected.to match(%r{#{ipv6_network}\s+#{router1_ip6}\s+0\s+32768\s+i}) }
    end
    describe command("vtysh -c \'show ipv6 bgp neighbors #{router3_ip6} advertised-routes\'") do
      its(:stdout) { is_expected.to match(%r{#{ipv6_network}\s+#{router1_ip6}\s+0\s+32768\s+i}) }
    end
  end
end
