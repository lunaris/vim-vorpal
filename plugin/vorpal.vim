if exists('g:loaded_vorpal') || &cp
  finish
endif
let g:loaded_vorpal = 1

if !exists('g:vorpal_drush_executable')
  let g:vorpal_drush_executable = 'drush'
endif

" Utilities.

function! s:function(name) abort
  return function(substitute(a:name, '^s:',
    \ matchstr(expand('<sfile>'), '<SNR>\d\+_'), ''))
endfunction

function! s:throw(error_message) abort
  let v:errmsg= 'vorpal: ' . a:error_message
  throw v:errmsg
endfunction

function! s:sub(s, pattern, replacement) abort
  return substitute(a:s, '\v\C' . a:pattern, a:replacement, '')
endfunction

function! s:gsub(s, pattern, replacement) abort
  return substitute(a:s, '\v\C' . a:pattern, a:replacement, 'g')
endfunction

function! s:shellslash(path)
  if exists('+shellslash') && !&shellslash
    return s:gsub(a:path, '\\', '/')
  else
    return a:path
  endif
endfunction

function! s:add_methods(namespace, methods) abort
  for method in a:methods
    let s:{a:namespace}_prototype[method] =
      \ s:function('s:' . a:namespace . '_' . method)
  endfor
endfunction

let s:commands = []

function! s:command(definition) abort
  let s:commands += [a:definition]
endfunction

function! s:define_commands()
  for command in s:commands
    exe 'command! -buffer ' . command
  endfor
endfunction

augroup vorpal_utility
  autocmd!
  autocmd User Vorpal call s:define_commands()
augroup END

" Initialisation.

" Returns 1 iff the supplied path is a Drupal directory.
"
" TODO: This won't work for Drupal 8.
function! vorpal#is_drupal_dir(path) abort
  let path = s:sub(a:path, '[\/]$', '') . '/'
  return isdirectory(path . 'includes') && isdirectory(path . 'modules') &&
    \ isdirectory(path . 'profiles') && isdirectory(path . 'sites') &&
    \ isdirectory(path . 'themes')
endfunction

" Returns 1 iff the supplied path contains a .info file.
function! vorpal#has_info_file(path) abort
  let path = s:sub(a:path, '[\/]$', '') . '/'
  return glob(path . '*.info') !=# ''
endfunction

" Extracts information about the hierarchy of the given path, including
" library, module, profile or theme directories and the parent Drupal
" directory. In the event that the supplied path does not belong to a Drupal
" directory hierarchy, this function returns an empty dictionary.
function! vorpal#extract_drupal_dirs(path) abort
  let current = s:shellslash(simplify(fnamemodify(a:path, ':p:s?[\/]$??')))
  let previous = ''

  let info_dir = ''
  let dirs = {}

  while current !=# previous
    let type = getftype(current)
    if vorpal#is_drupal_dir(current)
      if type ==# 'dir'
        let dirs['drupal'] = {'path': current}
      elseif type ==# 'link'
        let dirs['drupal'] = {'path': resolve(current)}
      endif

      return dirs
    endif

    if vorpal#has_info_file(current)
      if type ==# 'dir'
        let info_dir = current
      elseif type ==# 'link'
        let info_dir = resolve(current)
      endif
    endif

    let current_tail = fnamemodify(current, ':t')
    if current_tail ==# 'libraries' && info_dir !=# ''
      let dirs['extension'] =
        \ {'type': 'library', 'name': fnamemodify(info_dir, ':t'),
          \ 'path': info_dir}
    elseif current_tail ==# 'modules' && info_dir !=# ''
      let dirs['extension'] =
        \ {'type': 'module', 'name': fnamemodify(info_dir, ':t'),
          \ 'path': info_dir}
    elseif current_tail ==# 'profiles' && info_dir !=# ''
      let dirs['extension'] =
        \ {'type': 'profile', 'name': fnamemodify(info_dir, ':t'),
          \ 'path': info_dir}
    elseif current_tail ==# 'themes' && info_dir !=# ''
      let dirs['extension'] =
        \ {'type': 'theme', 'name': fnamemodify(info_dir, ':t'),
          \ 'path': info_dir}
    endif

    let previous = current
    let current = fnamemodify(current, ':h')
  endwhile

  return {}
endfunction

" Detects whether or not the current buffer resides in a Drupal directory,
" loading Vorpal's commands in the case that it does.
function! s:detect(path)
  if exists('b:drupal_dirs') && b:drupal_dirs == {}
    unlet b:drupal_dir
  endif

  if !exists('b:drupal_dirs')
    let dirs = vorpal#extract_drupal_dirs(a:path)
    if dirs !=# {}
      let b:drupal_dirs = dirs
    endif
  endif

  if exists('b:drupal_dirs')
    silent doautocmd User Vorpal

    let buffer = vorpal#buffer()
    let tags_file = b:drupal_dirs['drupal']['path'] . '/tags'

    if stridx(buffer.get_var('&tags'), escape(tags_file, ', ')) == -1 &&
        \ filereadable(tags_file)

      call buffer.set_var('&tags', escape(tags_file, ', ') .
        \ ',' . buffer.get_var('&tags'))
    endif
  endif
endfunction

augroup vorpal
  autocmd!
  autocmd BufNewFile,BufReadPost * call s:detect(expand('<amatch>:p'))
  autocmd User NERDTreeInit,NERDTreeNewRoot call s:detect(expand('%:p'))
  autocmd VimEnter * if expand('<amatch>')==''|call s:detect(getcwd())|endif
augroup END

" File types.

augroup vorpal_file_types
  autocmd!
  autocmd BufEnter *.engine,*.inc,*.install,*.module,*.php,*.profile,*.test
    \ if exists('b:drupal_dirs') |
      \ set filetype=php |
      \ if exists('did_UltiSnips_vim') |
        \ UltiSnipsAddFiletypes drupal.php |
      \ endif |
    \ endif
augroup END

" Prototype namespaces.

let s:abstract_prototype = {}

let s:buffer_prototype = {}

let s:drupal_prototype = {}

let s:extension_prototype = {}
let s:module_prototype = {}
let s:theme_prototype = {}

" Buffers.

function! s:buffer(...) abort
  let buffer = {'#': bufnr(a:0 ? a:1 : '%')}
  call extend(extend(buffer, s:buffer_prototype, 'keep'),
    \ s:abstract_prototype, 'keep')

  if buffer.get_var('drupal_dirs') != {}
    return buffer
  endif

  call s:throw('not a Drupal file: ' . expand('%:p'))
endfunction

function! vorpal#buffer(...) abort
  return s:buffer(a:0 ? a:1 : '%')
endfunction

function! s:buffer_get_var(name) dict abort
  return getbufvar(self['#'], a:name)
endfunction

function! s:buffer_set_var(name, value) dict abort
  return setbufvar(self['#'], a:name, a:value)
endfunction

function! s:buffer_line(number) dict abort
  return getbufline(self['#'], a:number)[0]
endfunction

function! s:buffer_drupal_dirs() dict abort
  return getbufvar(self['#'], 'drupal_dirs')
endfunction

function! s:buffer_drupal() dict abort
  let drupal_dirs = self.drupal_dirs()
  if has_key(drupal_dirs, 'drupal')
    let drupal = drupal_dirs['drupal']
    call extend(extend(drupal, s:drupal_prototype, 'keep'),
      \ s:abstract_prototype, 'keep')

    return drupal
  endif

  return {}
endfunction

function! s:buffer_extension() dict abort
  let drupal_dirs = self.drupal_dirs()
  if has_key(drupal_dirs, 'extension')
    let extension = drupal_dirs['extension']

    call extend(extend(extend(extension,
      \ s:{extension['type']}_prototype, 'keep'),
        \ s:extension_prototype, 'keep'), s:abstract_prototype, 'keep')

    return extension
  endif

  return {}
endfunction

function! s:buffer_library() dict abort
  let extension = self.extension()
  return extension != {} && extension['type'] ==# 'library' ?
    extension : {}
endfunction

function! s:buffer_module() dict abort
  let extension = self.extension()
  return extension != {} && extension['type'] ==# 'module' ?
    \ extension : {}
endfunction

function! s:buffer_profile() dict abort
  let extension = self.extension()
  return extension != {} && extension['type'] ==# 'profile' ?
    \ extension : {}
endfunction

function! s:buffer_theme() dict abort
  let extension = self.extension()
  return extension != {} && extension['type'] ==# 'theme' ?
    \ extension : {}
endfunction

call s:add_methods('buffer',
  \ ['get_var', 'set_var', 'line', 'drupal_dirs', 'drupal',
    \ 'extension', 'library', 'module', 'profile', 'theme'])

" Extensions (modules, themes, etc.).

" Returns the name of the current extension's .info file.
function s:extension_info() dict abort
  return self.path . '/' . self.name . '.info'
endfunction

" Opens the current extension's .info file for editing.
function! s:EditInfo() abort
  let extension = vorpal#buffer().extension()
  if extension != {}
    execute 'edit ' . extension.info()
  endif
endfunction

call s:add_methods('extension', ['info'])

call s:command('-nargs=0 DrupalEditInfo :execute s:EditInfo()')

" Modules.

" Returns the name of the current modules .install file.
function! s:module_install() dict abort
  return self.path . '/' . self.name . '.install'
endfunction

" Returns the name of the current module's .module file.
function! s:module_module() dict abort
  return self.path . '/' . self.name . '.module'
endfunction

" Opens the current module's .install file for editing.
function! s:EditModuleInstall() abort
  let module = vorpal#buffer().module()
  if module != {}
    execute 'edit' module.install()
  endif
endfunction

" Opens the current module's .module file for editing.
function! s:EditModuleModule() abort
  let module = vorpal#buffer().module()
  if module != {}
    execute 'edit' module.module()
  endif
endfunction

function! s:GotoModuleHookMenu() abort
  let module = vorpal#buffer().module()
  if module != {}
    execute 'tag' module.name . '_menu'
  endif
endfunction

call s:add_methods('module', ['install', 'module'])

call s:command('-nargs=0 DrupalEditModuleInstall :execute s:EditModuleInstall()')
call s:command('-nargs=0 DrupalEditModuleModule :execute s:EditModuleModule()')
call s:command('-nargs=0 DrupalGotoModuleHookMenu :execute s:GotoModuleHookMenu()')

" Drush.

" Executes the given command in the current buffer's Drupal directory.
function! s:execute_in_drupal_dir(cmd) abort
  let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd ' : 'cd '
  let dir = getcwd()

  try
    execute cd . '`=s:buffer().drupal().path`'
    execute a:cmd
  finally
    execute cd . '`=dir`'
  endtry
endfunction

" Runs the given drush command. If a bang is appended (as in Drush!), passes
" the -y option to drush (which answers yes to all prompts).
function! s:Drush(bang, cmd) abort
  if a:bang
    let drush = g:vorpal_drush_executable . ' -y'
  else
    let drush = g:vorpal_drush_executable
  endif

  let cmd = matchstr(a:cmd, '\v\C.{-}%($|\\@<!%(\\\\)*\|)@=')

  call s:execute_in_drupal_dir('!' . drush . ' ' . cmd)
  return matchstr(a:cmd, '\v\C\\@<!%(\\\\)*\|\zs.*')
endfunction

call s:command('-bang -nargs=* Drush :execute s:Drush(<bang>0, <q-args>)')

" Clears the named cache. If no name is given, clears all caches.
function! s:DrushCacheClear(...) abort
  let cache = 'all'
  if a:0 > 0
    let cache = a:1
  endif

  call s:Drush(0, 'cache-clear ' . cache)
endfunction

" Clears parts of Drupal's cache based on the current buffer's file type. In
" cases where the cache to be cleared can't be accurately determined, clears
" all caches.
function! s:DrushCacheClearSmart() abort
  " We're really not that smart.
  let cache = 'all'

  " We don't expect more than two extensions (.tpl.php and .views.inc being two
  " notable examples).
  let extension = expand("%:p:e:e")
  if extension ==# 'css'
    let cache = 'css-js'
  elseif extension ==# 'js'
    let cache = 'css-js'
  elseif extension ==# 'tpl.php'
    let cache = 'theme-registry'
  elseif extension ==# 'views.inc'
    let cache = 'views'
  endif

  call s:DrushCacheClear(cache)
endfunction

call s:command('-nargs=? DrushCacheClear :execute s:DrushCacheClear(<q-args>)')
call s:command('-nargs=0 DrushCacheClearSmart :execute s:DrushCacheClearSmart()')

" Reinstalls the given list of modules, or the current module if no arguments
" are provided.
function! s:DrushReinstall(bang, ...) abort
  if a:0 > 0
    let modules = join(a:000)
  else
    let module = vorpal#buffer().module()
    if module != {}
      let modules = module.name
    endif
  endif

  call s:Drush(a:bang, 'devel-reinstall ' . modules)
endfunction

call s:command('-bang -nargs=* DrushReinstall :execute s:DrushReinstall(<bang>0, <args>)')

" Complete functions.

function! s:until_start_of_word() abort
  let line = getline('.')
  let start = col('.') - 1
  while start > 0 && line[start - 1] =~ '\a'
    let start -= 1
  endwhile

  return start
endfunction

function! s:until_char(c) abort
  let line = getline('.')
  let start = col('.') - 1
  while start > 0 && line[start - 1] !=# a:c
    let start -= 1
  endwhile

  return start
endfunction

function! s:until_hash() abort
  return s:until_char('#')
endfunction

function! vorpal#complete_form_item(findstart, base) abort
  if a:findstart
    return s:until_hash()
  else

  endif
endfunction

function! vorpal#complete_form_item_type(findstart, base) abort
  if a:findstart
    return s:until_start_of_word()
  else
    let types = [
      \ {'word': 'checkbox'},
      \ {'word': 'checkboxes'},
      \ {'word': 'date'},
      \ {'word': 'fieldset'},
      \ {'word': 'file'},
      \ {'word': 'machine_name'},
      \ {'word': 'managed_file'},
      \ {'word': 'password'},
      \ {'word': 'password_confirm'},
      \ {'word': 'radio'},
      \ {'word': 'radios'},
      \ {'word': 'select'},
      \ {'word': 'tableselect'},
      \ {'word': 'text_format'},
      \ {'word': 'textarea'},
      \ {'word': 'textfield'},
      \ {'word': 'vertical_tabs'},
      \ {'word': 'weight'}
    \ ]

    let results = []
    for type in types
      if type['word'] =~ '^' . a:base
        call add(results, type)
      endif
    endfor

    return results
  endif
endfunction


