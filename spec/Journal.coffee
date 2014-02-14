if typeof process isnt 'undefined' and process.execPath and process.execPath.indexOf('node') isnt -1
  chai = require 'chai' unless chai
  graph = require '../src/lib/Graph.coffee'
  journal = require '../src/lib/Journal.coffee'
  network = require '../src/lib/Network.coffee'
else
  graph = require 'noflo/src/lib/Graph.js'
  journal = require 'noflo/src/lib/Journal.js'
  network = require 'noflo/src/lib/Network.js'

describe 'Journal', ->
  describe 'connected to initialized graph', ->
    g = new graph.Graph
    g.addNode 'Foo', 'Bar'
    g.addNode 'Baz', 'Foo'
    g.addEdge 'Foo', 'out', 'Baz', 'in'
    j = new journal.Journal(g)
    it 'should have just the initial transaction', ->
      chai.expect(j.lastRevision).to.equal 0

  describe 'following basic graph changes', ->
    g = new graph.Graph
    j = new journal.Journal(g)
    it 'should create one transaction per change', ->
      g.addNode 'Foo', 'Bar'
      g.addNode 'Baz', 'Foo'
      g.addEdge 'Foo', 'out', 'Baz', 'in'
      chai.expect(j.lastRevision).to.equal 3
      g.removeNode 'Baz'
      chai.expect(j.lastRevision).to.equal 4

  describe 'pretty printing', ->
    g = new graph.Graph
    j = new journal.Journal(g)

    g.startTransaction 'test1'
    g.addNode 'Foo', 'Bar'
    g.addNode 'Baz', 'Foo'
    g.addEdge 'Foo', 'out', 'Baz', 'in'
    g.addInitial 42, 'Foo', 'in'
    g.removeNode 'Foo'
    g.endTransaction 'test1'

    g.startTransaction 'test2'
    g.removeNode 'Baz'
    g.endTransaction 'test2'

    it 'should be human readable', ->
      ref = """>>> 0: initial
        <<< 0: initial
        >>> 1: test1
        Foo(Bar)
        Baz(Foo)
        Foo out -> in Baz
        '42' -> in Foo
        Foo out -X> in Baz
        '42' -X> in Foo
        DEL Foo(Bar)
        <<< 1: test1"""
      chai.expect(j.toPrettyString(0,2)).to.equal ref

  describe 'jumping to revision', ->
    g = new graph.Graph
    j = new journal.Journal(g)
    g.addNode 'Foo', 'Bar'
    g.addNode 'Baz', 'Foo'
    g.addEdge 'Foo', 'out', 'Baz', 'in'
    g.addInitial 42, 'Foo', 'in'
    g.removeNode 'Foo'
    it 'should change the graph', ->
      j.recallRevision 0
      chai.expect(g.nodes.length).to.equal 0
      j.recallRevision 2
      chai.expect(g.nodes.length).to.equal 2
      j.recallRevision 5
      chai.expect(g.nodes.length).to.equal 1

  describe 'linear undo/redo', ->
    g = new graph.Graph
    j = new journal.Journal(g)
    g.addNode 'Foo', 'Bar'
    g.addNode 'Baz', 'Foo'
    g.addEdge 'Foo', 'out', 'Baz', 'in'
    g.addInitial 42, 'Foo', 'in'
    graphBeforeError = g.toJSON()
    chai.expect(g.nodes.length).to.equal 2
    it 'undo should restore previous revision', ->
      g.removeNode 'Foo'
      chai.expect(g.nodes.length).to.equal 1
      j.undo()
      chai.expect(g.nodes.length).to.equal 2
      chai.expect(g.toJSON()).to.deep.equal graphBeforeError
    it 'redo should apply the same change again', ->
      j.redo()
      chai.expect(g.nodes.length).to.equal 1
    it 'undo should also work multiple revisions back', ->
      g.removeNode 'Baz'
      j.undo()
      j.undo()
      chai.expect(g.nodes.length).to.equal 2
      chai.expect(g.toJSON()).to.deep.equal graphBeforeError

  describe 'divergent branch', ->
    g = new graph.Graph
    j = new journal.Journal(g)
    g.addNode 'Foo', 'Bar'
    g.addNode 'Baz', 'Foo'
    g.addEdge 'Foo', 'out', 'Baz', 'in'
    g.addInitial 42, 'Foo', 'in'
    g.addNode 'Baz2', 'Component1'
    firstHead =
      graph: g.toJSON()
      revision: j.currentRevision
    otherHead = null
    chai.expect(j.currentRevision).to.equal 5

    it 'undo and making changes should only append to journal', ->
      j.undo()
      chai.expect(g.nodes.length).to.equal 2
      chai.expect(j.currentRevision).to.equal firstHead.revision+1
      g.addNode 'OtherBaz2', 'Component2'
      chai.expect(j.currentRevision).to.equal firstHead.revision+2
      chai.expect(g.nodes.length).to.equal 3
      chai.expect(g.nodes[2].component).to.equal 'Component2'
      otherHead =
        graph: g.toJSON()
        revision: j.currentRevision

    it 'one can go back to a revision which is not part of current branch', ->
      j.recallRevision(firstHead.revision)
      chai.expect(g.nodes.length).to.equal 3
      chai.expect(g.nodes[2].component).to.equal 'Component1'

    it 'and this action is also revisioned and can be reverted', ->
#      chai.expect(j.currentRevision).to.equal otherHead.revision+1
#      j.recallRevision(otherHead)
#      chai.expect(g.toJSON()).to.equal otherHead
#      chai.expect(j.currentRevision).to.equal otherHead.revision+2

    it 'it possible to peek into journal without changing graph', ->
#      peek = j.peekAtRevision()
#      peek.graph
#      peek.metadata

  describe 'undoing a node removal', ->
    g = new graph.Graph
    j = new journal.Journal(g)
    n = new network.Network(g)

    # TODO: build network of some real components, that stores state
    # Take one of the nodes out, then try to undo the change

    it 'should restore the same node', ->

    it 'and its internal state be preserved', ->


# FIXME: add tests for graph.loadJSON/loadFile, and journal metadata

