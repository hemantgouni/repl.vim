" repl.vim: Use your language's repl right from a vim buffer!
" Copyright (C) 2021 Hemant Sai Gouni

" This program is free software: you can redistribute it and/or modify
" it under the terms of the GNU Affero General Public License as
" published by the Free Software Foundation, either version 3 of the
" License, or (at your option) any later version.

" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU Affero General Public License for more details.

" You should have received a copy of the GNU Affero General Public License
" along with this program.  If not, see <https://www.gnu.org/licenses/>.

" the terminal buffer in which the repl is
let s:repl_buffer = -1

" the window in which the repl buffer is currently
let s:repl_window = -1

" the job id (see the return value of 'jobstart()') for
" the repl buffer
let s:repl_job_identifier = -1

" yank: String
" @returns: String

function! s:Get_text_with(yank)

    " save the current cursor position; it may
    " be changed by the yank
    let l:cursor_position_current = getcurpos()

    " save the state of the register we're about
    " to use
    let l:old_reg_value = getreg()

    let l:old_reg_type = getregtype()

    " run the yank command
    execute "normal! " . a:yank

    " get the result of the yank command
    let l:reg_value = getreg()

    " restore the contents of the register; v:register is
    " used by default for normal mode commands
    call setreg(v:register, l:old_reg_value, l:old_reg_type)
    
    " restore the position of the cursor
    call cursor(l:cursor_position_current[1:])

    " return the yanked text
    return l:reg_value

endfunction

" Send some text to the specified repl
"
" repl: String
" preprocessor: String -> String
" string: String
" @gets: s:repl_job_identifier
" @returns: Unit

function! s:Send_to_repl(repl, preprocessor, string)

    " Ensure the repl is displayed
    call Repl_show(a:repl)

    " We probably want to use a lambda here (instead of arguments to set
    " delimiters), because for other languages, inserting characters after lines
    " to indicate continued input is probably necessary (and others)
    let l:repl_input_string = a:preprocessor(a:string)

    " send the string to the standard input of the repl job
    call chansend(s:repl_job_identifier, l:repl_input_string)

    " jump to the end of the buffer immediately;
    " this ensures that the buffer will autoscroll
    "
    " think of a cleaner way to do this?
    call win_execute(s:repl_window, 'normal! G')

endfunction

" repl: String
" @sets: s:repl_buffer
" @sets: s:repl_window
" @sets: s:repl_job_identifier
" @returns: Unit

function! s:Make_repl_window(repl)

        " make a new split window, and a new buffer in it
        " analogous to `split <bar> enew`
        "
        " this buffer is named so we can remove it later,
        " and avoid leaking buffers (shown in :buffers! or
        " ls!)
        new repl

        " attempt to switch to the terminal buffer
        " inside the split
        try

            " switch to the terminal buffer,
            " if there is one
            execute "buffer " . s:repl_buffer

            " remove the unneeded buffer here
            "
            " we don't write 'bd repl' here because we
            " want to avoid accidental variable capture (ie,
            " 'repl' could be a local variable)
            execute "bd repl"

        " if it does not exist, make a new terminal buffer
        catch

            " record the buffer number; we will use this to
            " revive the buffer into a new window later
            let s:repl_buffer = bufnr()

            " create the repl; record the repl's job
            " identifier so we can send text to it
            let s:repl_job_identifier = termopen(a:repl)

            " set local options for the buffer
            setlocal nocursorline

        endtry

        " record the new window identifier
        let s:repl_window = win_getid()

endfunction

" Hide the repl if it is currently shown,
" show the repl if it is currently hidden
"
" repl: String
" @gets: s:repl_window
" @gets: s:repl_buffer
" @returns: Unit

function! s:Repl_toggle(repl)

    " test if the window containing the repl buffer
    " is the last one open
    "
    " if so, we should make a new window before we switch to the
    " repl buffer and hide it
    "
    " winnr('$') returns the window count...? because it returns
    " the number of the last open window i think.
    "
    " comparing to winnr() does not work, because winnr() just returns the
    " window number of the current window, which may be == to winnr('$') if
    " we're in the last window
    "
    " if buffwinnr returns -1, then there is no window containing
    " the specified buffer
    if winnr('$') == 1 && bufwinnr(s:repl_buffer) != -1

        new

        call win_gotoid(s:repl_window)

        hide

    " if a window containing the terminal buffer
    " exists, remove it (untoggle)
    elseif win_gotoid(s:repl_window)

        " hide does not 'hide' the window; it
        " quits it without deleting the buffer
        hide

    " otherwise, make the terminal window
    else

        call Make_repl_window(a:repl)

        " enter insert mode
        startinsert!

    endif

endfunction

" Show the repl unconditionally
"
" repl: String
" @gets: s:repl_buffer
" @returns: Unit

function! s:Repl_show(repl)

    " if we create a new window, we'll switch to it, so we should save our
    " current window
    let l:current_window = win_getid()

    " bufwinnr returns -1 if a window does not contain
    " the given buffer; if so, we should make the
    " window
    "
    " could also use bufwinid() here, since we usually work with window
    " identifiers
    if bufwinid(s:repl_buffer) == -1

        call Make_repl_window(a:repl)

    endif

    " if the window we should be at is not equivalent to our current window
    " (as indicated by win_getid), we should switch to the correct window
    if l:current_window != win_getid()

        call win_gotoid(l:current_window)

    endif

endfunction

augroup Haskell_repl_config
    autocmd!
    " we use <SID> here so vim knows exactly which function to call when these
    " mappings are invoked from outside the script
    autocmd FileType haskell nnoremap <silent><localleader>r :call <SID>Repl_toggle("ghci")<CR>

    autocmd FileType haskell inoremap <silent><localleader>r <ESC>:call <SID>Repl_toggle("ghci")<CR>

    autocmd FileType haskell tnoremap <silent><localleader>r <C-\><C-n>:call <SID>Repl_toggle("ghci")<CR>

    " lambdas don't require a: in front of their argument variables within
    " their bodies
    autocmd FileType haskell nnoremap <silent><localleader>e :call <SID>Send_to_repl("ghci",
                \ { string -> count(string, "\n") > 1 ? ":{\n" . string . ":}\n" : string },
                \ <SID>Get_text_with("yip"))
                \ <CR>

    autocmd FileType haskell nnoremap <silent><localleader>t :call <SID>Send_to_repl("ghci",
                \ { string -> ":type " . string . "\n" },
                \ <SID>Get_text_with("yiw"))
                \ <CR>
augroup END
