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
        let dirs['drupal'] = current
      elseif type ==# 'link'
        let dirs['drupal'] = resolve(current)
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
      let dirs['library'] =
        \ {'name': fnamemodify(info_dir, ':t'), 'path': info_dir}
    elseif current_tail ==# 'modules' && info_dir !=# ''
      let dirs['module'] =
        \ {'name': fnamemodify(info_dir, ':t'), 'path': info_dir}
    elseif current_tail ==# 'profiles' && info_dir !=# ''
      let dirs['profile'] =
        \ {'name': fnamemodify(info_dir, ':t'), 'path': info_dir}
    elseif current_tail ==# 'themes' && info_dir !=# ''
      let dirs['theme'] =
        \ {'name': fnamemodify(info_dir, ':t'), 'path': info_dir}
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
  endif
endfunction

augroup vorpal
  autocmd!
  autocmd BufNewFile,BufReadPost * call s:detect(expand('<amatch>:p'))
  autocmd User NERDTreeInit,NERDTreeNewRoot call s:detect(expand('%:p'))
  autocmd VimEnter * if expand('<amatch>')==''|call s:detect(getcwd())|endif
augroup END

let s:abstract_prototype = {}

" File types.

augroup vorpal_file_types
  autocmd!
  autocmd BufEnter *.engine,*.inc,*.install,*.module,*.profile,*.test
    \ if exists('b:drupal_dirs') |
      \ set filetype=php |
    \ endif
augroup END

" Buffers

let s:buffer_prototype = {}

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

call s:add_methods('buffer', ['get_var', 'set_var', 'line', 'drupal_dirs'])

" Modules.

function! s:AddModuleHook(name) abort
  let drupal_dirs = vorpal#buffer().drupal_dirs()
  if has_key(drupal_dirs, 'module')
    call append(line('.'),
      \ 'function ' . drupal_dirs['module']['name'] . '_' . a:name . '() {}')
  endif
endfunction

call s:command('-nargs=1 Dhook :execute s:AddModuleHook("<args>")')
