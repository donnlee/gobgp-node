Gobgp = require('../index')
gobgp = new Gobgp('localhost:50051')

expect = require('chai').expect
exec   = require('child_process').execSync

describe 'gobgp-node', ->
  global_rib = ->
    JSON.parse(exec('gobgp -j global rib'))

  flowspec_rib = ->
    JSON.parse(exec('gobgp -j global rib -a ipv4-flowspec'))

  communities = (prefix) ->
    table = global_rib()
    paths = table.filter (i) -> i['prefix']==prefix
    return if paths.empty?

    comms = paths[0]['paths'][0]['attrs'].filter (i) -> i['type']==8
    return comms[0]['communities']

  PREFIX = '10.0.0.0/24'
  FLOWSPEC_PREFIX = "match source #{PREFIX} then rate-limit 10000"

  beforeEach ->
    exec "gobgp global rib del #{PREFIX}"
    exec "gobgp global rib -a ipv4-flowspec del #{FLOWSPEC_PREFIX}"


  describe 'family ipv4-unicast', ->
    it 'originates a route', ->
      expect(global_rib()).to.be.empty

      gobgp.addPath family: 'ipv4-unicast', PREFIX

      table = global_rib()
      expect(table.length).to.equal 1
      expect(table[0]['prefix']).to.equal PREFIX

    it 'originates a route with BGP community string', ->
      expect(global_rib()).to.be.empty

      gobgp.addPath family: 'ipv4-unicast', "#{PREFIX} community no-advertise"

      table = global_rib()
      expect(table.length).to.equal 1
      expect(table[0]['prefix']).to.equal PREFIX

      expect(communities(PREFIX)).to.eql [4294967042]

    it 'originates a route with BGP community byte array', ->
      expect(global_rib()).to.be.empty

      path = gobgp.serializePath('ipv4-unicast', PREFIX)
      path.pattrs.push new Buffer([
        0xc0,                      # Optional, Transitive
        0x08,                      # Type Code: Communities
        0x04,                      # Length
        0xff, 0xff, 0xff, 0x02])  # NO_ADVERTISE

      gobgp.addPath family: 'ipv4-unicast', path

      table = global_rib()
      expect(table.length).to.equal 1
      expect(table[0]['prefix']).to.equal PREFIX

      expect(communities(PREFIX)).to.eql [4294967042]

    it 'shows the RIB', ->  # TODO: This does actually nothing. Use chai-as-promised
      exec "gobgp global rib add #{PREFIX}"

      gobgp.getRib family: 'ipv4-unicast', (err, table) ->
        expect(table['type']).to.equal 'GLOBAL'
        expect(table['family']).to.equal 65537
        expect(table['destinations'].length).to.equal 1

        path = table['destinations'][0]
        expect(path['prefix']).to.equal PREFIX

    it 'withdraws a route', ->
      exec "gobgp global rib add #{PREFIX}"
      expect(global_rib()).not.to.be.empty

      gobgp.deletePath family: 'ipv4-unicast', PREFIX

      expect(global_rib()).to.be.empty


  describe 'family ipv4-flowspec', ->
    it 'originates a route', ->
      expect(flowspec_rib()).to.be.empty

      gobgp.addPath family: 'ipv4-flowspec', FLOWSPEC_PREFIX

      table = flowspec_rib()
      expect(table.length).to.equal 1
      expect(table[0].prefix).to.equal "[source:#{PREFIX}]"

    it 'shows the RIB', ->  # TODO: This does actually nothing. Use chai-as-promised
      exec "gobgp global rib -a ipv4-flowspec add #{FLOWSPEC_PREFIX}"

      gobgp.getRib family: 'ipv4-flowspec', (err, table) ->
        expect(table.type).to.equal 'GLOBAL'
        expect(table.family).to.equal 65669
        expect(table.destinations.length).to.equal 1

        path = table.destinations[0]
        expect(path.prefix).to.equal "[source:#{PREFIX}]"
        expect(path.paths[0].attrs[2].value[0].rate).to.equal 10000

    it 'withdraws a route', ->
      exec "gobgp global rib -a ipv4-flowspec add #{FLOWSPEC_PREFIX}"
      expect(flowspec_rib()).not.to.be.empty

      gobgp.deletePath family: 'ipv4-flowspec', FLOWSPEC_PREFIX

      expect(flowspec_rib()).to.be.empty


  describe 'backward compatibility for modPath', ->
    it 'originates a route', ->
      expect(global_rib()).to.be.empty

      gobgp.modPath family: 'ipv4-unicast', PREFIX

      table = global_rib()
      expect(table.length).to.equal 1
      expect(table[0]['prefix']).to.equal PREFIX

    it 'withdraws a route', ->
      exec "gobgp global rib add #{PREFIX}"
      expect(global_rib()).not.to.be.empty

      gobgp.modPath family: 'ipv4-unicast', withdraw: true, PREFIX

      expect(global_rib()).to.be.empty
