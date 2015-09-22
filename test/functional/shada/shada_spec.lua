-- Other ShaDa tests
local helpers = require('test.functional.helpers')
local nvim, nvim_window, nvim_curwin, nvim_command, nvim_feed, nvim_eval, eq =
  helpers.nvim, helpers.window, helpers.curwin, helpers.command, helpers.feed,
  helpers.eval, helpers.eq
local write_file, spawn, set_session, nvim_prog, exc_exec =
  helpers.write_file, helpers.spawn, helpers.set_session, helpers.nvim_prog,
  helpers.exc_exec
local lfs = require('lfs')
local paths = require('test.config.paths')

local msgpack = require('MessagePack')

local shada_helpers = require('test.functional.shada.helpers')
local reset, set_additional_cmd, clear, get_shada_rw =
  shada_helpers.reset, shada_helpers.set_additional_cmd,
  shada_helpers.clear, shada_helpers.get_shada_rw
local read_shada_file = shada_helpers.read_shada_file

local wshada, sdrcmd, shada_fname, clean = get_shada_rw('Xtest-functional-shada-shada.shada')

describe('ShaDa support code', function()
  before_each(reset)
  after_each(function()
    clear()
    clean()
  end)

  it('preserves `s` item size limit with unknown entries', function()
    wshada('\100\000\207\000\000\000\000\000\000\004\000\218\003\253' .. ('-'):rep(1024 - 3)
           .. '\100\000\207\000\000\000\000\000\000\004\001\218\003\254' .. ('-'):rep(1025 - 3))
    eq(0, exc_exec('wshada ' .. shada_fname))
    local found = 0
    for _, v in ipairs(read_shada_file(shada_fname)) do
      if v.type == 100 then
        found = found + 1
      end
    end
    eq(2, found)
    eq(0, exc_exec('set shada-=s10 shada+=s1'))
    eq(0, exc_exec('wshada ' .. shada_fname))
    found = 0
    for _, v in ipairs(read_shada_file(shada_fname)) do
      if v.type == 100 then
        found = found + 1
      end
    end
    eq(1, found)
  end)

  it('preserves `s` item size limit with instance history entries', function()
    local hist1 = ('-'):rep(1024 - 5)
    local hist2 = ('-'):rep(1025 - 5)
    nvim_command('set shada-=s10 shada+=s1')
    nvim_eval(('histadd(":", "%s")'):format(hist1))
    nvim_eval(('histadd(":", "%s")'):format(hist2))
    eq(0, exc_exec('wshada ' .. shada_fname))
    local found = 0
    for _, v in ipairs(read_shada_file(shada_fname)) do
      if v.type == 4 then
        found = found + 1
        eq(hist1, v.value[2])
      end
    end
    eq(1, found)
  end)

  it('leaves .tmp.a in-place when there is error in original ShaDa', function()
    wshada('Some text file')
    eq('Vim(wshada):E576: Error while reading ShaDa file: last entry specified that it occupies 109 bytes, but file ended earlier', exc_exec('wshada ' .. shada_fname))
    eq(1, read_shada_file(shada_fname .. '.tmp.a')[1].type)
  end)

  it('does not leave .tmp.a in-place when there is error in original ShaDa, but writing with bang', function()
    wshada('Some text file')
    eq(0, exc_exec('wshada! ' .. shada_fname))
    eq(1, read_shada_file(shada_fname)[1].type)
    eq(nil, lfs.attributes(shada_fname .. '.tmp.a'))
  end)

  it('leaves .tmp.b in-place when there is error in original ShaDa and it has .tmp.a', function()
    wshada('Some text file')
    eq('Vim(wshada):E576: Error while reading ShaDa file: last entry specified that it occupies 109 bytes, but file ended earlier', exc_exec('wshada ' .. shada_fname))
    eq('Vim(wshada):E576: Error while reading ShaDa file: last entry specified that it occupies 109 bytes, but file ended earlier', exc_exec('wshada ' .. shada_fname))
    eq(1, read_shada_file(shada_fname .. '.tmp.a')[1].type)
    eq(1, read_shada_file(shada_fname .. '.tmp.b')[1].type)
  end)

  it('leaves .tmp.z in-place when there is error in original ShaDa and it has .tmp.a … .tmp.x', function()
    wshada('Some text file')
    local i = ('a'):byte()
    while i < ('z'):byte() do
      write_file(shada_fname .. ('.tmp.%c'):format(i), 'Some text file', true)
      i = i + 1
    end
    eq('Vim(wshada):E576: Error while reading ShaDa file: last entry specified that it occupies 109 bytes, but file ended earlier', exc_exec('wshada ' .. shada_fname))
    eq(1, read_shada_file(shada_fname .. '.tmp.z')[1].type)
  end)

  it('errors out when there are .tmp.a … .tmp.z ShaDa files', function()
    wshada('')
    local i = ('a'):byte()
    while i <= ('z'):byte() do
      write_file(shada_fname .. ('.tmp.%c'):format(i), '', true)
      i = i + 1
    end
    eq('Vim(wshada):E138: All Xtest-functional-shada-shada.shada.tmp.X files exist, cannot write ShaDa file!', exc_exec('wshada ' .. shada_fname))
  end)

  it('reads correctly various timestamps', function()
    local mpack = {
      '\100',  -- Positive fixnum 100
      '\204\255',  -- uint 8 255
      '\205\010\003',  -- uint 16 2563
      '\206\255\010\030\004',  -- uint 32 4278853124
      '\207\005\100\060\250\255\010\030\004',  -- uint 64 388502516579048964
    }
    local s = '\100'
    local e = '\001\192'
    wshada(s .. table.concat(mpack, e .. s) .. e)
    eq(0, exc_exec('wshada ' .. shada_fname))
    local found = 0
    local typ = select(2, msgpack.unpacker(s)())
    for _, v in ipairs(read_shada_file(shada_fname)) do
      if v.type == typ then
        found = found + 1
        eq(select(2, msgpack.unpacker(mpack[found])()), v.timestamp)
      end
    end
    eq(#mpack, found)
  end)

  it('does not write NONE file', function()
    local session = spawn({nvim_prog, '-u', 'NONE', '-i', 'NONE', '--embed',
                           '--cmd', 'qall'}, true)
    session:exit(0)
    eq(nil, lfs.attributes('NONE'))
    eq(nil, lfs.attributes('NONE.tmp.a'))
  end)

  it('does not read NONE file', function()
    write_file('NONE', '\005\001\015\131\161na\162rX\194\162rc\145\196\001-')
    local session = spawn({nvim_prog, '-u', 'NONE', '-i', 'NONE', '--embed'},
                          true)
    set_session(session)
    eq('', nvim_eval('@a'))
    session:exit(0)
    os.remove('NONE')
  end)

  it('correctly uses shada-r option', function()
    nvim('set_var', '__home', paths.test_source_path)
    nvim_command('let $HOME = __home')
    nvim_command('unlet __home')
    nvim_command('edit ~/README.md')
    nvim_command('normal! GmAggmaAabc')
    nvim_command('undo')
    nvim_command('set shada+=%')
    nvim_command('wshada! ' .. shada_fname)
    local marklike = {[7]=true, [8]=true, [10]=true, [11]=true}
    local readme_fname = paths.test_source_path .. '/README.md'
    local find_readme = function()
      local found = {}
      for _, v in ipairs(read_shada_file(shada_fname)) do
        if marklike[v.type] and v.value.f == readme_fname then
          found[v.type] = (found[v.type] or 0) + 1
        elseif v.type == 9 then
          for _, b in ipairs(v.value) do
            if b.f == readme_fname then
              found[v.type] = (found[v.type] or 0) + 1
            end
          end
        end
      end
      return found
    end
    eq({[7]=1, [8]=2, [9]=1, [10]=4, [11]=1}, find_readme())
    nvim_command('set shada+=r~')
    nvim_command('wshada! ' .. shada_fname)
    eq({}, find_readme())
    nvim_command('set shada-=r~')
    nvim_command('wshada! ' .. shada_fname)
    eq({[7]=1, [8]=2, [9]=1, [10]=4, [11]=1}, find_readme())
    nvim_command('set shada+=r' .. paths.test_source_path)
    nvim_command('wshada! ' .. shada_fname)
    eq({}, find_readme())
  end)
end)
