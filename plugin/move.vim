" =============================================================================
" File: plugin/move.vim
" Description: Move lines and selections up and even down.
" Author: Matthias Vogelgesang <github.com/matze>
" =============================================================================

if exists('g:loaded_move') || &compatible
    finish
endif

let g:loaded_move = 1

if !exists('g:move_map_keys')
    let g:move_map_keys = 1
endif

if !exists('g:move_key_modifier')
    let g:move_key_modifier = 'A'
endif

if !exists('g:move_auto_indent')
    let g:move_auto_indent = 1
endif

if !exists('g:move_past_end_of_line')
    let g:move_past_end_of_line = 1
endif

function! s:SaveDefaultRegister()
   let s:default_register_value = @"
endfunction

function! s:RestoreDefaultRegister()
   let @" = s:default_register_value
endfunction

"
" In visual mode, move the selected lines vertically.
" Moves down if (distance > 0) and up if (distance < 0).
"
function s:MoveBlockVertically(distance)
    if !&modifiable
        return
    endif

    let l:first = line("'<")
    let l:last  = line("'>")

    if a:distance <= 0
        let l:after = max([1,         l:first + a:distance]) - 1
    else
        let l:after = min([line('$'), l:last  + a:distance])
    endif
    execute 'silent' l:first ',' l:last 'move ' l:after

    if g:move_auto_indent
        normal! gv=
    endif

    normal! gv
endfunction

"
" In visual mode, move the selected block to the left
" Switches to visual-block mode first if another visual mode is selected.
"
function! s:MoveBlockLeft(distance) range
    let l:min_col = min([virtcol("'<"), virtcol("'>")])
    let l:distance = min([a:distance, l:min_col - 1])

    if !&modifiable || virtcol("$") == 1 || l:distance <= 0 || visualmode() ==# "V"
        normal! gv
        return
    endif

    if visualmode() ==# "v" && a:lastline - a:firstline > 0
        execute "silent normal! gv\<C-v>"
        echomsg "Switching to visual block mode for moving multiple lines with MoveBlockLeft"
        return
    endif

    let [l:old_virtualedit, &virtualedit] = [&virtualedit, 'onemore']
    call s:SaveDefaultRegister()

    " save previous cursor position
    silent normal! gv
    let l:row_pos = getcurpos()[1]
    let l:is_rhs = virtcol(".") == max([virtcol("'<"), virtcol("'>")])

    execute 'silent normal! gvd' . l:distance . "hP`[\<C-v>`]"

    " restore previous cursor position
    if getcurpos()[1] != l:row_pos
        silent normal! o
        if l:is_rhs
           silent normal! O
        endif
    elseif !l:is_rhs
        silent normal! O
    endif

    call s:RestoreDefaultRegister()
    let &virtualedit = l:old_virtualedit
endfunction

"
" In visual mode, move the selected block to the right
" Switches to visual-block mode first if another visual mode is selected.
"
function! s:MoveBlockRight(distance) range
    let l:max_col = max([virtcol("'<"), virtcol("'>")])

    let l:distance = a:distance
    if !g:move_past_end_of_line
        let l:shorter_line_len = min(map(getline(a:firstline, a:lastline), 'strwidth(v:val)'))
        let l:distance = min([l:shorter_line_len - l:max_col, l:distance])
    end

    if !&modifiable || virtcol("$") == 1 || l:distance <= 0
        normal! gv
        return
    endif

    if visualmode() ==# "V"
        execute "silent normal! gv\<C-v>o0o$h"
        echomsg "Switching to visual block mode for moving whole line(s) with MoveBlockRight"
        return
    endif

    if visualmode() ==# "v" && a:lastline - a:firstline > 0
        execute "silent normal! gv\<C-v>"
        echomsg "Switching to visual block mode for moving multiple lines with MoveBlockRight"
        return
    endif


    let [l:old_virtualedit, &virtualedit] = [&virtualedit, 'all']
    call s:SaveDefaultRegister()

    " save previous cursor position
    silent normal! gv
    let l:row_pos = getcurpos()[1]
    let l:is_rhs = virtcol(".") == l:max_col

    execute 'silent normal! gvd' . l:distance . "l"
    " P behaves inconsistently in virtualedit 'all' mode; sometimes the cursor
    " moves one right after pasting, other times it doesn't. This makes it
    " difficult to rely on `[ to determine the start of the shifted selection.
    let l:new_start_pos = virtcol(".")
    execute 'silent normal! P' . l:new_start_pos . "|\<C-v>`]"

    " restore previous cursor position
    if getcurpos()[1] != l:row_pos
        silent normal! o
        if l:is_rhs
           silent normal! O
        endif
    elseif !l:is_rhs
        silent normal! O
    endif

    call s:RestoreDefaultRegister()
    let &virtualedit = l:old_virtualedit
endfunction

"
" In normal mode, move the current line vertically.
" Moves down if (distance > 0) and up if (distance < 0).
"
function! s:MoveLineVertically(distance)
    if !&modifiable
        return
    endif

    " Remember the current cursor position. When we move or reindent a line
    " Vim will move the cursor to the first non-blank character.
    let l:old_cursor_col = virtcol('.')
    silent normal! ^
    let l:old_indent     = virtcol('.')

    if a:distance <= 0
        let l:after = max([1,         line('.') + a:distance]) - 1
    else
        let l:after = min([line('$'), line('.') + a:distance])
    endif
    execute 'silent move' l:after

    if g:move_auto_indent
        silent normal! ==
    endif

    " Restore the cursor column, taking indentation changes into account.
    let l:new_indent = virtcol('.')
    let l:new_cursor_col = max([1, l:old_cursor_col - l:old_indent + l:new_indent])
    execute 'silent normal!'  l:new_cursor_col . '|'
endfunction

"
" In normal mode, move the character under the cursor horizontally
" Moves right (distance > 0) and left if (distance < 0).
"
function! s:MoveCharHorizontally(distance)
    if !&modifiable
        return
    endif

    let l:curr = virtcol('.')
    let l:next = l:curr + a:distance
    if !g:move_past_end_of_line
        let l:next = max([1, min([l:next, virtcol('$')-1])])
    endif

    if l:curr == l:next
        " Don't add an empty change to the undo stack.
        return
    endif

    call s:SaveDefaultRegister()
    let [l:old_virtualedit, &virtualedit] = [&virtualedit, 'all']

    normal! x
    execute 'normal!' . (l:next.'|')
    normal! P

    let &virtualedit = l:old_virtualedit
    call s:RestoreDefaultRegister()

endfunction

function! s:HalfPageSize()
    return winheight('.') / 2
endfunction

function! s:MoveKey(key)
    return '<' . g:move_key_modifier . '-' . a:key . '>'
endfunction


vnoremap <silent> <Plug>MoveBlockDown           :<C-u> call <SID>MoveBlockVertically( v:count1)<CR>
vnoremap <silent> <Plug>MoveBlockUp             :<C-u> call <SID>MoveBlockVertically(-v:count1)<CR>
vnoremap <silent> <Plug>MoveBlockHalfPageDown   :<C-u> call <SID>MoveBlockVertically( v:count1 * <SID>HalfPageSize())<CR>
vnoremap <silent> <Plug>MoveBlockHalfPageUp     :<C-u> call <SID>MoveBlockVertically(-v:count1 * <SID>HalfPageSize())<CR>
vnoremap <silent> <Plug>MoveBlockLeft           :call <SID>MoveBlockLeft(v:count1)<CR>
vnoremap <silent> <Plug>MoveBlockRight          :call <SID>MoveBlockRight(v:count1)<CR>

" We can't use functions defined with the 'range' attribute for moving lines
" or characters. In the case of lines, it causes vim to complain with E16
" (Invalid adress) if we try to move out of bounds. In the case of characters,
" it messes up the result of calling col().
nnoremap <silent> <Plug>MoveLineDown            :<C-u> call <SID>MoveLineVertically( v:count1)<CR>
nnoremap <silent> <Plug>MoveLineUp              :<C-u> call <SID>MoveLineVertically(-v:count1)<CR>
nnoremap <silent> <Plug>MoveLineHalfPageDown    :<C-u> call <SID>MoveLineVertically( v:count1 * <SID>HalfPageSize())<CR>
nnoremap <silent> <Plug>MoveLineHalfPageUp      :<C-u> call <SID>MoveLineVertically(-v:count1 * <SID>HalfPageSize())<CR>
nnoremap <silent> <Plug>MoveCharRight           :<C-u> call <SID>MoveCharHorizontally( v:count1)<CR>
nnoremap <silent> <Plug>MoveCharLeft            :<C-u> call <SID>MoveCharHorizontally(-v:count1)<CR>


if g:move_map_keys
    execute 'vmap' s:MoveKey('j') '<Plug>MoveBlockDown'
    execute 'vmap' s:MoveKey('k') '<Plug>MoveBlockUp'
    execute 'vmap' s:MoveKey('h') '<Plug>MoveBlockLeft'
    execute 'vmap' s:MoveKey('l') '<Plug>MoveBlockRight'

    execute 'nmap' s:MoveKey('j') '<Plug>MoveLineDown'
    execute 'nmap' s:MoveKey('k') '<Plug>MoveLineUp'
    execute 'nmap' s:MoveKey('h') '<Plug>MoveCharLeft'
    execute 'nmap' s:MoveKey('l') '<Plug>MoveCharRight'
endif
