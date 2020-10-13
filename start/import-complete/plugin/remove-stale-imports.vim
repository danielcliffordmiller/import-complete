
function! s:removeStaleImports()
  let l:lines = getbufline(bufname(""),0,"$")
  call map(l:lines, '[v:key+1, v:val]')
  call filter(l:lines, "match(get(v:val, 1), '^import') == 0")

  let s:lastImport = get(get(l:lines, len(l:lines)-1), 0)

  let l:pos = getpos('.')
  let l:startRow = get(l:pos, 1)

  call filter(l:lines, function('s:filterImports'))

  call sort(l:lines, function('s:sortFunc'))

  let l:removed = 0
  for [row, line] in l:lines
    if row < l:startRow
      let l:removed = l:removed + 1
    endif
  endfor

  call map(l:lines, "deletebufline(bufname(''), get(v:val, 0))")

  let l:pos[1] = l:startRow - l:removed

  call setpos('.', l:pos)
endfunction

function! s:sortFunc(a, b)
  return get(a:b, 0) - get(a:a, 0)
endfunction

function! s:filterImports(key, import)
  return get(a:import, 1) !~ '\*;\?$' && s:checkImport(a:import)
endfunction

function! s:checkImport(importLine)
  let [l:row, l:importLine] = a:importLine
  call cursor(l:row, 0)
  let l:startRow = s:curRow()
  normal $b*

  let l:endRow = s:curRow()

  while l:startRow != l:endRow && l:endRow <= s:lastImport
    normal n
    let l:endRow = s:curRow()
  endwhile

  return l:startRow == l:endRow
endfunction

function! s:curRow()
  return get(getpos('.'), 1)
endfunction

noremap <unique> <script> <Plug>ImportsRemoveStale :call <SID>removeStaleImports()<CR>
nmap <leader>I <Plug>ImportsRemoveStale
