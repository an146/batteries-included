(* 
 * Stream - streams and stream parsers
 * Copyright (C) 1997 Daniel de Rauglaudre
 *               2007 Zheng Li
 *               2008 David Teller
 * 
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version,
 * with the special exception on linking described in file LICENSE.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *)


open Stream

    type 'a enumerable = 'a t
    type 'a mappable = 'a t

    exception End_of_flow = Failure
      
    let ( |> ) x f = f x
      
    let ( @. ) f x = f x
      
    let ( |- ) f g x = g (f x)
      
    let ( -| ) f g x = f (g x)
      
    let ( // ) f g (x, y) = ((f x), (g y))
      
    let curry f x y = f (x, y)
      
    let uncurry f (x, y) = f x y
      
    let id x = x
      
    let rec of_fun f =
      Stream.slazy
        (fun _ ->
           try
             let h = f ()
             in Stream.icons h (Stream.slazy (fun _ -> of_fun f))
           with | End_of_flow -> Stream.sempty)
      
    let to_fun fl () = next fl
      
    let to_list fl =
      let buf = ref []
      in (iter (fun x -> buf := x :: !buf) fl; List.rev !buf)
      
    let to_string fl =
      let sl = to_list fl in
      let len = List.length sl in
      let s = String.create len
      in (List.iter (let i = ref 0 in fun x -> (s.[!i] <- x; incr i)) sl; s)
      
    let on_channel ch = iter (output_char ch)
      
    let on_output o = iter (BatIO.write o)
      
    let rec of_input i =
      Stream.slazy
        (fun _ ->
           try
             let h = BatIO.read i
             in Stream.icons h (Stream.slazy (fun _ -> of_input i))
           with | BatIO.No_more_input -> Stream.sempty)
      
    let rec cycle times x =
      match times with
      | None -> Stream.iapp x (Stream.slazy (fun _ -> cycle None x))
      | Some 1 -> x
      | (* in case of destriction *) Some n when n <= 0 -> Stream.sempty
      | Some n ->
          Stream.iapp x (Stream.slazy (fun _ -> cycle (Some (n - 1)) x))
      
    let rec repeat times x = cycle times (Stream.ising x)
      
    let rec seq init step cont =
      if cont init
      then
        Stream.icons init (Stream.slazy (fun _ -> seq (step init) step cont))
      else Stream.sempty
      
    let rec range n until =
      let step x = (x + 1) land max_int in
      let cont =
        match until with | None -> (fun x -> true) | Some x -> ( >= ) x
      in seq n step cont
      
    let ( -- ) p q = range p (Some q)
      
    let next (__strm : _ Stream.t) =
      match Stream.peek __strm with
      | Some h -> (Stream.junk __strm; h)
      | _ -> raise End_of_flow
      
    let rec foldl f init s =
      match peek s with
      | Some h ->
          (match f init h with
           | (accu, None) -> (junk s; foldl f accu s)
           | (accu, Some true) -> (junk s; accu)
           | (_, Some false) -> init)
      | None -> init
      
    let rec foldr f init s =
      let (__strm : _ Stream.t) = s
      in
        match Stream.peek __strm with
        | Some h -> (Stream.junk __strm; f h (lazy (foldr f init s)))
        | _ -> init
      
    let fold f s =
      let (__strm : _ Stream.t) = s
      in
        match Stream.peek __strm with
        | Some h -> (Stream.junk __strm; foldl f h s)
        | _ -> raise End_of_flow
      
    let cons x s = Stream.icons x s
      
    let apnd s1 s2 = Stream.iapp s1 s2
      
    let is_empty s = match peek s with | None -> true | _ -> false
      
    let rec concat ss =
      Stream.slazy
        (fun _ ->
           let (__strm : _ Stream.t) = ss
           in
             match Stream.peek __strm with
             | Some p ->
                 (Stream.junk __strm;
                  Stream.iapp p (Stream.slazy (fun _ -> concat ss)))
             | _ -> Stream.sempty)
      
    let rec filter f s =
      Stream.slazy
        (fun _ ->
           let (__strm : _ Stream.t) = s
           in
             match Stream.peek __strm with
             | Some h ->
                 (Stream.junk __strm;
                  if f h
                  then Stream.icons h (Stream.slazy (fun _ -> filter f s))
                  else Stream.slazy (fun _ -> filter f s))
             | _ -> Stream.sempty)
      
    let take n fl =
      let i = ref n
      in
        of_fun
          (fun () -> (if !i <= 0 then raise End_of_flow else decr i; next fl))
      
    let drop n fl =
      let i = ref n in
      let rec f () =
        if !i <= 0 then next fl else (ignore (next fl); decr i; f ())
      in of_fun f
      
    let rec take_while f s =
      Stream.slazy
        (fun _ ->
           match peek s with
           | Some h ->
               if f h
               then
                 (junk s;
                  Stream.icons h (Stream.slazy (fun _ -> take_while f s)))
               else Stream.sempty
           | None -> Stream.sempty)
      
    let rec drop_while f s =
      Stream.slazy
        (fun _ ->
           let (__strm : _ Stream.t) = s
           in
             match Stream.peek __strm with
             | Some h ->
                 (Stream.junk __strm;
                  if f h
                  then Stream.slazy (fun _ -> drop_while f s)
                  else Stream.icons h s)
             | _ -> Stream.sempty)
      
    let span p s =
      let q = Queue.create () and sr = ref None in
      let rec get_head () =
        Stream.slazy
          (fun _ ->
             if not (Queue.is_empty q)
             then
               Stream.lcons (fun _ -> Queue.take q) (Stream.slazy get_head)
             else
               (let (__strm : _ Stream.t) = s
                in
                  match Stream.peek __strm with
                  | Some h ->
                      (Stream.junk __strm;
                       if p h
                       then Stream.icons h (Stream.slazy get_head)
                       else (sr := Some h; Stream.sempty))
                  | _ -> Stream.sempty)) in
      let rec get_tail () =
        match !sr with
        | Some v -> Stream.icons v s
        | None ->
            Stream.slazy
              (fun _ ->
                 let (__strm : _ Stream.t) = s
                 in
                   match Stream.peek __strm with
                   | Some h ->
                       (Stream.junk __strm;
                        if p h then Queue.add h q else sr := Some h;
                        get_tail ())
                   | _ -> Stream.sempty)
      in ((get_head ()), (Stream.slazy get_tail))
      
    let break p s = span (p |- not) s
      
    let rec group p s =
      Stream.slazy
        (fun _ ->
           match peek s with
           | None -> Stream.sempty
           | Some v -> if p v then group_aux p s else group_aux (p |- not) s)
    and group_aux p s =
      match peek s with
      | None -> Stream.sempty
      | Some _ ->
          let h = next s in
          let (s1, s2) = span p s
          in
            Stream.lcons (fun _ -> Stream.icons h s1)
              (Stream.slazy (fun _ -> group_aux (p |- not) s2))
      
    let rec map f s =
      Stream.slazy
        (fun _ ->
           let (__strm : _ Stream.t) = s
           in
             match Stream.peek __strm with
             | Some h ->
                 (Stream.junk __strm;
                  Stream.lcons (fun _ -> f h)
                    (Stream.slazy (fun _ -> map f s)))
             | _ -> Stream.sempty)
      
    let dup s =
      let rec gen s qa qb =
        Stream.slazy
          (fun _ ->
             if not (Queue.is_empty qa)
             then
               Stream.lcons (fun _ -> Queue.take qa)
                 (Stream.slazy (fun _ -> gen s qa qb))
             else
               (let (__strm : _ Stream.t) = s
                in
                  match Stream.peek __strm with
                  | Some h ->
                      (Stream.junk __strm;
                       Queue.add h qb;
                       Stream.icons h (Stream.slazy (fun _ -> gen s qa qb)))
                  | _ -> Stream.sempty)) in
      let q1 = Queue.create ()
      and q2 = Queue.create ()
      in ((gen s q1 q2), (gen s q2 q1))
      
    let rec combn sa =
      Stream.slazy
        (fun _ ->
           if Array.fold_left (fun b s -> b || (is_empty s)) false sa
           then Stream.sempty
           else
             Stream.lcons (fun _ -> Array.map next sa)
               (Stream.slazy (fun _ -> combn sa)))
      
    let rec comb (s1, s2) =
      Stream.slazy
        (fun _ ->
           match peek s1 with
           | Some h1 ->
               (match peek s2 with
                | Some h2 ->
                    (junk s1;
                     junk s2;
                     Stream.lcons (fun _ -> (h1, h2))
                       (Stream.slazy (fun _ -> comb (s1, s2))))
                | None -> Stream.sempty)
           | None -> Stream.sempty)
      
    let dupn n s =
      let qa = Array.init n (fun _ -> Queue.create ()) in
      let rec gen i =
        Stream.slazy
          (fun _ ->
             if not (Queue.is_empty qa.(i))
             then
               Stream.lcons (fun _ -> Queue.take qa.(i))
                 (Stream.slazy (fun _ -> gen i))
             else
               (let (__strm : _ Stream.t) = s
                in
                  match Stream.peek __strm with
                  | Some h ->
                      (Stream.junk __strm;
                       for i = 0 to n - 1 do Queue.add h qa.(i) done;
                       gen i)
                  | _ -> Stream.sempty))
      in Array.init n gen
      
    let splitn n s =
      let qa = Array.init n (fun _ -> Queue.create ()) in
      let rec gen i =
        Stream.slazy
          (fun _ ->
             if not (Queue.is_empty qa.(i))
             then
               Stream.lcons (fun _ -> Queue.take qa.(i))
                 (Stream.slazy (fun _ -> gen i))
             else
               (let (__strm : _ Stream.t) = s
                in
                  match Stream.peek __strm with
                  | Some h ->
                      (Stream.junk __strm;
                       for i = 0 to n - 1 do Queue.add h.(i) qa.(i) done;
                       gen i)
                  | _ -> Stream.sempty))
      in Array.init n gen
      
    let split s = ( |- ) dup ((map fst) // (map snd)) s
      
    let mergen f sa =
      let n = Array.length sa in
      let pt = Array.init n id in
      let rec alt x i =
        (i < n) &&
          (if pt.((x + i) mod n) = pt.(x)
           then alt x (i + 1)
           else
             (for j = 0 to i - 1 do pt.((x + j) mod n) <- pt.((x + i) mod n)
              done;
              true)) in
      let rec aux i =
        Stream.slazy
          (fun _ ->
             let (__strm : _ Stream.t) = sa.(pt.(i))
             in
               match Stream.peek __strm with
               | Some h ->
                   (Stream.junk __strm;
                    let i' = pt.(i)
                    in
                      Stream.icons h
                        (Stream.slazy (fun _ -> aux pt.((f i' h) mod n))))
               | _ -> if alt i 1 then aux i else Stream.sempty)
      in aux 0
      
    let merge f (s1, s2) =
      let i2b = function | 0 -> true | 1 -> false | _ -> assert false
      and b2i = function | true -> 0 | false -> 1
      in mergen (fun i x -> b2i (f (i2b i) x)) [| s1; s2 |]
      
    let switchn n f s =
      let qa = Array.init n (fun _ -> Queue.create ()) in
      let rec gen i =
        Stream.slazy
          (fun _ ->
             if not (Queue.is_empty qa.(i))
             then
               Stream.lcons (fun _ -> Queue.take qa.(i))
                 (Stream.slazy (fun _ -> gen i))
             else
               (let (__strm : _ Stream.t) = s
                in
                  match Stream.peek __strm with
                  | Some h ->
                      (Stream.junk __strm;
                       let i' = (f h) mod n
                       in
                         if i' = i
                         then Stream.icons h (Stream.slazy (fun _ -> gen i))
                         else
                           (Queue.add h qa.(i');
                            Stream.slazy (fun _ -> gen i)))
                  | _ -> Stream.sempty))
      in Array.init n gen
      
    let switch f s =
      let sa = switchn 2 (fun x -> if f x then 0 else 1) s
      in ((sa.(0)), (sa.(1)))
      
    let rec scanl f init s =
      Stream.slazy
        (fun _ ->
           let (__strm : _ Stream.t) = s
           in
             match Stream.peek __strm with
             | Some h ->
                 (Stream.junk __strm;
                  Stream.icons init
                    (Stream.slazy (fun _ -> scanl f (f init h) s)))
             | _ -> Stream.ising init)
      
    let scan f s =
      Stream.slazy
        (fun _ ->
           let (__strm : _ Stream.t) = s
           in
             match Stream.peek __strm with
             | Some h ->
                 (Stream.junk __strm; Stream.slazy (fun _ -> scanl f h s))
             | _ -> Stream.sempty)
      
    let map2 f = (comb |- (map (uncurry f))) |> curry
      
    let rec map_fold f s =
      Stream.slazy
        (fun _ ->
           match peek s with
           | None -> Stream.sempty
           | Some _ ->
               Stream.lcons (fun _ -> fold f s)
                 (Stream.slazy (fun _ -> map_fold f s)))
      
    let feed stf vf delay exp =
      let s_in' = ref Stream.sempty in
      let out = exp (Stream.iapp delay (Stream.slazy (fun _ -> !s_in'))) in
      let s_in = stf out and s_out = vf out in (s_in' := s_in; s_out)
      
    let feedl delay exp = feed fst snd delay exp
      
    let feedr delay exp = feed snd fst delay exp
      
    let circ delay exp = feedl delay (exp |- dup)
      
    let while_do size test exp =
      let size = match size with | Some n when n >= 1 -> n | _ -> 1 in
      let inside = ref 0 in
      let judge x = if test x then (incr inside; true) else false in
      let choose b _ = (if not b then decr inside else (); !inside < size)
      in
        ((((merge choose) |- (switch judge)) |- (exp // id)) |> curry) |-
          (feedl Stream.sempty)
      
    let do_while size test exp =
      let size = match size with | Some n when n >= 1 -> n | _ -> 1 in
      let inside = ref 0 in
      let judge x = if test x then (incr inside; true) else false in
      let choose b _ = (if not b then decr inside else (); !inside < size)
      in
        ((((merge choose) |- exp) |- (switch judge)) |> curry) |-
          (feedl Stream.sempty)
      
    let farm par size path exp_gen s =
      let par = match par with | None -> 1 | Some p -> p in
      let size = match size with | None -> (fun _ -> 1) | Some f -> f in
      let path =
        match path with
        | None -> ignore |- (to_fun @. (cycle None (0 -- (par - 1))))
        | Some f -> f in
      let par = if par < 1 then 1 else par in
      let count = Array.make par 0 in
      let size x = let s = size x in if s < 1 then 1 else s in
      let path x = let i = path x in (count.(i) <- succ count.(i); i) in
      let choose =
        let rec find_next cond last i =
          if i < par
          then
            (let j = (last + i) mod par
             in if cond j then Some j else find_next cond last (i + 1))
          else None
        in
          fun last _ ->
            (count.(last) <- count.(last) - 1;
             let nth =
               match find_next (fun i -> count.(i) >= (size i)) last 1 with
               | Some j -> j
               | None ->
                   (match find_next (fun i -> count.(i) > 0) last 1 with
                    | Some j -> j
                    | None -> last + (1 mod par))
             in nth) in
      let sa_in = switchn par path s in
      let sa_out = Array.mapi exp_gen sa_in in mergen choose sa_out
      
    let ( ||| ) exp1 exp2 = exp1 |- exp2
      
    let enum x =
      BatEnum.from
        (fun () ->
           try next x with | End_of_flow -> raise BatEnum.No_more_elements)
      
    let rec of_enum e =
      Stream.slazy
        (fun _ ->
           match BatEnum.get e with
           | Some h -> Stream.icons h (Stream.slazy (fun _ -> of_enum e))
           | None -> Stream.sempty)
      
module StreamLabels =
  struct
      
    let iter ~f x = iter f x
      
    let switch ~f x = switch f x
      
    let foldl ~f ~init = foldl f init
      
    let foldr ~f ~init = foldr f init
      
    let fold ~f ~init = fold f init
      
    let filter ~f = filter f
      
    let map ~f = map f
      
    let map2 ~f = map2 f
      
    let scanl ~f = scanl f
      
    let scan ~f = scan f
      
    let while_do ?size ~f = while_do size f
      
    let do_while ?size ~f = do_while size f
      
    let range ?until p = range p until
      
    let repeat ?times = repeat times
      
    let cycle ?times = cycle times
      
    let take_while ~f = take_while f
      
    let drop_while ~f = drop_while f
      
    let span ~f = span f
      
    let break ~f = break f
      
    let group ~f = group f
      
    let merge ~f = merge f
      
    let mergen ~f = mergen f
      
    let switchn x ~f = switchn x f
      
    let farm ?par ?size ?path = farm par size path
      
  end
  

