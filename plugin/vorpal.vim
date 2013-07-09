if exists('g:loaded_vorpal') || &cp
  finish
endif
let g:loaded_vorpal = 1

if !exists('g:vorpal_drush_executable')
  let g:vorpal_drush_executable = 'drush'
endif

if !exists('g:vorpal_drush_default_site_alias')
  let g:vorpal_drush_default_site_alias = ''
endif

if !exists('g:vorpal_auto_cache_clear_smart')
  let g:vorpal_auto_cache_clear_smart = 0
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

" Returns 1 iff the supplied path contains a PHPUnit directory.
function! vorpal#has_phpunit_dir(path) abort
  let path = s:sub(a:path, '[\/]$', '') . '/'
  return isdirectory(path . 'phpunit')
endfunction

" Returns 1 iff the supplied path contains a .info file.
function! vorpal#has_info_file(path) abort
  let path = s:sub(a:path, '[\/]$', '') . '/'
  return glob(path . '*.info') !=# ''
endfunction

function! vorpal#resolve_path(type, path) abort
  if a:type ==# 'dir'
    return a:path
  else
    return resolve(a:path)
  endif
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

    " Is it a Drupal directory?
    if vorpal#is_drupal_dir(current)
      let dirs['drupal'] = {'path': vorpal#resolve_path(type, current)}

      " Is there a PHPUnit directory?
      if vorpal#has_phpunit_dir(current)
        let dirs['phpunit'] =
              \ {'path': s:sub(vorpal#resolve_path(type, current), '[\/]$', '') .
              \ '/phpunit'}
      endif

      return dirs
    endif

    " If we've not already located an extension directory (i.e., a library,
    " module, profile or theme directory), is this one?
    if info_dir ==# '' && vorpal#has_info_file(current)
      let info_dir = vorpal#resolve_path(type, current)
    endif

    " Further up the directory hierarchy, we can work out the extension's type
    " (library, module, profile or theme), at which point we build the
    " extension dictionary.
    let current_tail = fnamemodify(current, ':t')
    if !has_key(dirs, 'extension') && info_dir !=# ''
      let name = fnamemodify(info_dir, ':t')
      if current_tail ==# 'libraries'
        let dirs['extension'] =
              \ {'type': 'library', 'name': name, 'path': info_dir}
      elseif current_tail ==# 'modules'
        let dirs['extension'] =
              \ {'type': 'module', 'name': name, 'path': info_dir}
      elseif current_tail ==# 'profiles'
        let dirs['extension'] =
              \ {'type': 'profile', 'name': name, 'path': info_dir}
      elseif current_tail ==# 'themes'
        let dirs['extension'] =
              \ {'type': 'theme', 'name': name, 'path': info_dir}
      endif
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

    let vorpal_file = b:drupal_dirs['drupal']['path'] . '/.vorpal'
    if filereadable(vorpal_file)
      execute "source " . vorpal_file
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

function! s:buffer_phpunit() dict abort
  let drupal_dirs = self.drupal_dirs()
  if has_key(drupal_dirs, 'phpunit')
    return drupal_dirs['phpunit']
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
      \ ['get_var', 'set_var', 'line', 'drupal_dirs', 'drupal', 'phpunit',
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

  if g:vorpal_drush_default_site_alias !=# ''
    let drush = drush . ' ' . g:vorpal_drush_default_site_alias
  endif

  let cmd = matchstr(a:cmd, '\v\C.{-}%($|\\@<!%(\\\\)*\|)@=')

  let value = @z
  call s:execute_in_drupal_dir('let @z = system("' . drush . ' ' . cmd . '")')
  let drush_output = @z
  let @z = value

  return drush_output
endfunction

call s:command('-bang -nargs=* Drush :execute s:Drush(<bang>0, <q-args>)')

" Clears the named cache. If no name is given, clears all caches.
function! s:DrushCacheClear(...) abort
  let cache = 'all'
  if a:0 > 0
    let cache = a:1
  endif

  call s:Drush(0, 'cache-clear ' . cache)
  echo "Caches cleared"
endfunction

" Clears parts of Drupal's cache based on the current buffer's file type. In
" cases where the cache to be cleared can't be accurately determined, clears
" all caches.
"
" TODO: Drupal 6 doesn't support all these different cache types.
function! s:DrushCacheClearSmart() abort
  " We're really not that smart.
  let cache = 'all'

  " We don't expect more than two extensions (.tpl.php and .views.inc being two
  " notable examples).
  let extension = expand("%:p:e:e")
  if extension ==# 'css' || extension ==# 'less' ||
    \ extension ==# 'js' || extension ==# 'scss'

    let cache = 'css-js'
  elseif extension ==# 'tpl.php'
    let cache = 'theme-registry'
  elseif extension ==# 'views.inc'
    let cache = 'views'
  endif

  call s:DrushCacheClear(cache)
endfunction

call s:command('-nargs=? DrushCacheClear :execute s:DrushCacheClear(<f-args>)')
call s:command('-nargs=0 DrushCacheClearSmart :execute s:DrushCacheClearSmart()')

augroup vorpal_auto_cache_clear_smart
  autocmd!
  autocmd BufWrite *.css,*.engine,*.inc,*.install,*.js,*.less,
    \*.php,*.profile,*.scss,*.test
    \
    \ if exists('b:drupal_dirs') |
      \ let theme = vorpal#buffer().theme() |
      \ if theme != {} && g:vorpal_auto_cache_clear_smart |
        \ echo "Clearing caches..." |
        \ silent! call s:DrushCacheClearSmart() |
        \ redraw! |
      \ endif |
    \ endif
augroup END

" Locates the directory of the given target and opens a new tab in which it may
" be explored.
function! s:DrushTabDirectory(target) abort
  let directory = s:Drush(0, 'dd ' . a:target)

  " Don't open a new tab if the current buffer is empty.
  if bufname("%") !=# ""
    tabnew
  endif

  execute 'lcd ' . directory
  Explore
endfunction

call s:command('-complete=custom,s:DrushExtensions -nargs=1 DrushTabDirectory :execute s:DrushTabDirectory(<f-args>)')

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

call s:command('-bang -complete=custom,s:DrushExtensions -nargs=* DrushReinstall :execute s:DrushReinstall(<bang>0, <args>)')

" Opens the unit test directory associated with the current module (or given
" list of modules) in a split or tab, depending on the command passed.
function! s:OpenUnitTestDirectory(open_command, ...) abort
  let phpunit = vorpal#buffer().phpunit()
  if phpunit !=# {}
    if a:0 == 0
      let current_module = vorpal#buffer().module()
      if current_module != {}
        let modules = [current_module.name]
      endif
    else
      let modules = a:000
    endif

    let phpunit_tests_path = phpunit.path . '/tests'
    for module in modules
      " Attempt to find a test directory specific to the current module,
      " falling back to the PHPUnit root directory if we can't.
      let path = phpunit_tests_path . '/' . module
      if !isdirectory(path)
        let path = phpunit_tests_path
      endif

      execute a:open_command
      execute 'lcd ' . path
      e.
    endfor
  endif
endfunction

call s:command('-complete=custom,s:DrushExtensions -nargs=* SplitUnitTestDirectory :execute s:OpenUnitTestDirectory("split", <f-args>)')
call s:command('-complete=custom,s:DrushExtensions -nargs=* VsplitUnitTestDirectory :execute s:OpenUnitTestDirectory("vsplit", <f-args>)')
call s:command('-complete=custom,s:DrushExtensions -nargs=* TabUnitTestDirectory :execute s:OpenUnitTestDirectory("tabnew", <f-args>)')

" Rebuilds the plugin's cache of available extensions.
function! s:drush_rebuild_extension_cache() abort
  let s:vorpal_extension_cache = s:Drush(0, 'pm-list --pipe')
endfunction

" Completion function for commands which operate on Drupal extensions.
function! s:DrushExtensions(lead, command_line, position) abort
  " Cache the list of available extensions to avoid waiting every time we
  " attempt a completion.
  if !exists('s:vorpal_extension_cache')
    call s:drush_rebuild_extension_cache()
  endif

  return s:vorpal_extension_cache
endfunction
