namespace Singularity.Apps {

    [DBus (name = "dev.sinty.Collab.Document1")]
    public class WriteCollabBus : Object {
        private unowned WriteApp app;

        public WriteCollabBus(WriteApp app) {
            this.app = app;
        }

        public void receive(string title, string payload, string from) throws Error {
            throw new IOError.NOT_SUPPORTED("Write opens shared documents through a session");
        }

        public void join(string session, string title, string snapshot, string role, string from) throws Error {
            app.join_collab(session, snapshot, from);
        }
    }
}
