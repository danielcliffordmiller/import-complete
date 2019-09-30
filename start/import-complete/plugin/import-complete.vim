
let s:javaTagsFile = 'java-classes-tags.json'

let s:importClass = []

function! s:localFunName(name)
  return '<SNR>' . matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_localFunName$') . '_' . a:name
endfunction

" this returns non-zero if an import
" statement already exists for this class
function! s:importExists(tag, class)
  call setpos('.', [0,0,0,0])

  let l:escapedTag =  substitute(a:tag,'\.','\\\.','g')

  if search('^\(\s\+\)\?import ' . l:escapedTag . '\.' . a:class)
    return v:true
  endif

  return search('^\(\s\+\)\?import ' . l:escapedTag . '\.\*')
endfunction

function! s:offsetPos(pos, offset)
  return [get(a:pos,0), get(a:pos,1) + a:offset, get(a:pos,2), get(a:pos,3)]
endfunction

function! s:addImport(tag,class)

  let l:curpos = getcurpos()
  let l:offset = 0

  if s:importExists(a:tag, a:class)
    call setpos('.', l:curpos)
    return
  endif

  call setpos('.', [0,0,0,0])

  let l:classList = split(a:tag, '\.')

  while len(l:classList)
    let l:escapedTag =  join(l:classList, '\.')
    let l:searchResult = search('^\(\s\+\)\?import ' . l:escapedTag)

    if l:searchResult
      break
    endif

    call remove(l:classList, -1)
  endwhile

  if l:searchResult == 0
    execute "normal oj"
    let l:offset += 1
  endif

  let l:execString = "normal Oimport " . a:tag . "." . a:class
  let l:offset += 1
  if s:fileExtension() ==# "java"
    let l:execString .= ";"
  endif

  execute l:execString

  call setpos('.', s:offsetPos(l:curpos, l:offset))

endfunction

" this function is just for testing
function! AddImport(class)
  let [l:tag, l:class] = split(a:class, '\.\([^.]\+$\)\@=')
  call s:addImport(l:tag, l:class)
endfunction

function! s:fileExtension()
  return matchstr( expand('%'), '\.\@<=[^\.]\+$' )
endfunction

function! s:loadTags()
  try
    return json_decode(join(readfile(s:javaTagsFile), ''))
  catch /E484/
    return {}
  endtry
endfunction

function! s:selectImport()
  let l:class = expand('<cword>')
  let l:tags = s:loadMenu(l:class)

  if len(l:tags) == 1
    let s:importClass = [ get(l:tags,0), l:class ]
  else
    execute "popup Imports." . l:class
  endif

  if len(s:importClass) == 0 | return | endif

  let [l:tag, l:class] = s:importClass
  call s:addImport(l:tag, l:class)
  let s:importClass = []
  execute "unmenu Imports." . l:class
endfunction

function! s:setImportClass(tag, class)
  let s:importClass = [a:tag, a:class]
endfunction

function! s:loadMenu(class)
  for tag in s:classTags[a:class]
    let l:escapedTag = substitute(tag, '\.', '\\\.', 'g')
    execute "menu Imports." . a:class . '.' . l:escapedTag . ' :call ' . s:localFunName('setImportClass') . "('" . l:tag . "','" . a:class . "')\<cr>"
  endfor

  return s:classTags[a:class]
endfunction

let s:classTags = s:loadTags()

nnoremap <leader>i :call <sid>selectImport()<cr>
