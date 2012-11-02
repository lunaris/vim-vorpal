if exists('g:loaded_vorpal') || &cp
  finish
endif
let g:loaded_vorpal = 1

if !exists('g:vorpal_drush_executable')
  let g:vorpal_drush_executable = 'drush'
endif

" Utilities.

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

" Extracts a parent Drupal directory from the given path, if one exists.
function! vorpal#extract_drupal_dir(path) abort
  let current = s:shellslash(simplify(fnamemodify(a:path, ':p:s?[\/]$??')))
  let previous = ''

  while current !=# previous
    let type = getftype(current)
    if type ==# 'dir' && vorpal#is_drupal_dir(current)
      return current
    elseif type ==# 'link' && vorpal#is_drupal_dir(current)
      return resolve(current)
    endif

    let previous = current
    let current = fnamemodify(current, ':h')
  endwhile
  return ''
endfunction
