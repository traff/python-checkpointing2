import hashlib
import collections

Frame = collections.namedtuple('Frame',
        ('f_lasti', 'stack_content', ))


def save_generator_state(gen):
    cdef PyFrameObject *frame = <PyFrameObject *>gen.gi_frame

    stack_size = frame.f_stacktop - frame.f_localsplus
    print "stack size for", gen, ":", stack_size
    stack_content = []
    for i in range(stack_size):
        stack_content.append(<object>frame.f_localsplus[i])
    return Frame(<object>frame.f_lasti, stack_content)


def restore_generator(gen, saved_frame):
    cdef PyFrameObject *frame = <PyFrameObject *>gen.gi_frame

    frame.f_lasti = saved_frame.f_lasti
    for i, o in enumerate(saved_frame.stack_content):
        # TODO: I need to increment the refcount for the stack content but i don't
        # know how to do that here.
        frame.f_valuestack[i] = <PyObject*> o

    return gen


funcall_log = {}
modules = []

def print_frame(frame):
    cdef PyFrameObject *f = <PyFrameObject *> frame

    if not frame:
        return 0

    indent = print_frame(frame.f_back)

    print ' ' * indent, frame.f_locals.get('func', '?'), f.f_lasti

    return indent + 1


cdef hash_code(f_code):
  h = hashlib.sha1(f_code.co_code)
  h.update(str(f_code.co_consts).encode("utf-8"))
  return h.digest()


cdef PyObject* pyeval_log_funcall_entry(PyFrameObject *frame, int exc):
  frame_obj = <object> frame
  cdef PyThreadState *state = PyThreadState_Get()

  # to ovoid the overhead of this call, log only if the function is in
  # the desired modules.
  if frame_obj.f_code.co_filename not in modules:
      state.interp.eval_frame = _PyEval_EvalFrameDefault
      r = _PyEval_EvalFrameDefault(frame, exc)
      state.interp.eval_frame = pyeval_log_funcall_entry
      return r

  print "---------Tracing-----"
  print frame_obj.f_code.co_filename, frame_obj.f_code.co_name

  # keep a fully qualified name for the function. and a sha1 of its code.
  # if we hold references to the frame object, we might cause a lot of
  # unexpected garbage to be kept around.
  funcall_log[(frame_obj.f_code.co_filename, frame_obj.f_code.co_name)] = hash_code(frame_obj.f_code)

  return _PyEval_EvalFrameDefault(frame, exc)


def trace_funcalls(module_fnames):
    cdef PyThreadState *state = PyThreadState_Get()
    modules.clear()
    modules.extend(module_fnames)
    state.interp.eval_frame = pyeval_log_funcall_entry


def stop_trace_funcalls():
    cdef PyThreadState *state = PyThreadState_Get()
    state.interp.eval_frame = _PyEval_EvalFrameDefault
