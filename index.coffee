{BufferedProcess, CompositeDisposable} = require 'atom'
{exists, unlink, writeFile} = require 'fs'
{join, resolve, dirname} = require 'path'
{randomBytes} = require 'crypto'
{tmpdir} = require 'os'

findFile = (dir, file, cb) ->
  absolute = join dir, file
  exists absolute, (doesExist) ->
    return cb absolute if doesExist
    parent = resolve dir, '..'
    return cb() if dir is parent
    findFile parent, file, cb

lint = (editor, command, args) ->
  filePath = editor.getPath()
  fileDir = dirname(filePath)
  tmpPath = join tmpdir(), randomBytes(32).toString 'hex'
  out = ''
  err = ''

  appendToOut = (data) -> out += data
  appendToErr = (data) -> err += data
  getConfig = (cb) -> findFile fileDir, '.rubocop.yml', cb
  getCwd = (cb) -> findFile fileDir, '', cb
  writeTmp = (cb) -> writeFile tmpPath, editor.getText(), cb
  cleanup = (cb) -> unlink tmpPath, cb

  new Promise (resolve, reject) -> getConfig (config) -> writeTmp (er) -> getCwd (cwd) ->
    return reject er if er
    new BufferedProcess
      command: command[0]
      args: [
        command.slice(1)...
        '-f'
        'json'
        (if config then ['-c', config] else [])...
        args...
        tmpPath
      ]
      options:
        cwd: cwd
      stdout: appendToOut
      stderr: appendToErr
      exit: -> cleanup ->
        try {offenses: errors} = JSON.parse(out).files[0]
        console.error err if err
        return reject new Error out unless errors
        resolve errors.map (error) ->
          {line, column, length} =
            error.location || {line: 1, column: 1, length: 0}
          type:
            switch error.severity
              when 'refactor', 'convention', 'warning' then 'warning'
              else 'error'
          text: (error.message or 'Unknown Error') +
            (if error.cop_name then " (#{error.cop_name})" else ''),
          filePath: filePath,
          range: [[line - 1, column - 1], [line - 1, column + length - 1]]

module.exports =
  config:
    executablePath:
      type: 'string'
      title: 'Executable Path'
      default: 'rubocop'
    additionalArguments:
      title: 'Additional Arguments'
      type: 'string'
      default: ''

  activate: ->
    prefix = 'linter-rubocop.'
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.config.observe "#{prefix}executablePath",
      (args) => @executablePath = if args then args.split ' ' else ['rubocop']
    @subscriptions.add atom.config.observe "#{prefix}additionalArguments",
      (args) => @additionalArguments = if args then args.split ' ' else []

  deactivate: ->
    @subscriptions.dispose()

  provideLinter: ->
    grammarScopes: ['source.ruby', 'source.ruby.rails', 'source.ruby.rspec'],
    scope: 'file'
    lintOnFly: true
    lint: (editor) => lint editor, @executablePath, @additionalArguments
