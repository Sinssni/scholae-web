package service;

import model.Role;
import model.Role.Roles;
import messages.ResponseMessage;
import messages.UserMessage;
import haxe.crypto.Md5;
import utils.StringUtils;
import messages.SessionMessage;
import model.Session;
import model.User;
import php.Lib.mail;

class AuthService {

    public function new() {}

    /**
    * return Session ID, String
    **/
    public function authenticate(email: String, password: String): SessionMessage {
        var user = User.getUserByEmailAndPassword(email, password);
        if (null != user) {
            var session = Session.getSessionByUser(user);
            if (null != session && null != Session.manager.search({ id: session.id }).first()) session.update() else session.insert();
            return user.toSessionMessage(session.id);
        }
        return null;
    }

    public function checkSession(sessionId: String): SessionMessage {
        var session: Session = Session.findSession(sessionId);

        return
            if (null != session)
                session.user.toSessionMessage(session.id)
            else
                null;
    }

    public function doesEmailExist(email: String): Bool {
        return User.manager.count($email == email) > 0;
    }

    public function doesCodeforcesHandleExist(codeforcesHandle: String): Bool {
        return User.manager.count($codeforcesHandle == codeforcesHandle) > 0;
    }

    public function isCodeforcesHandleValid(codeforcesHandle: String): Bool {
        //TODO: implement
        //use https://codeforces.com/api/help/methods#user.info to check if user exists
        return true;
    }

    public function renewPassword(email: String): Bool {
        var user: User = User.manager.select($email == email, true);
        var subjectForUser ='Scholae: измение пароля';
        var password = StringUtils.getRandomString(StringUtils.alphaNumeric, 8);
        var message = 'Здравствуйте,

ваш новый пароль: $password.

С уважением,
Scholae';
        var from = 'From: no-reply@scholae.lambda-calculus.ru';
        if (null != user) {
            var res = mail(user.email, subjectForUser, message, from);
            user.passwordHash = Md5.encode(password);
            user.update();
            return res;
        }
        else return false;
    }

    private function greetUser(user: User) {
        var subjectForUser ='Scholae: здравствуйте!';
        var message = 'Здравствуйте,

мы рады, что вы зарегистрировались в Scholae!

Удачи в тренировках!

С уважением,
Scholae';
        var from = 'From: no-reply@scholae.lambda-calculus.ru';
        mail(user.email, subjectForUser, message, from);
    }

    public function registerAndAuthenticateUser(user: UserMessage): ResponseMessage {
        if (doesEmailExist(user.email)) {
            return ServiceHelper.failResponse("Email already exists.");
        } else if (doesCodeforcesHandleExist(user.codeforcesHandle)) {
            return ServiceHelper.failResponse("Codeforces Handle already exists.");
        } else {
            var u: User = new User();
            u.email = user.email;
            u.firstName = user.firstName;
            u.lastName = user.lastName;
            u.passwordHash = Md5.encode(user.password);
            u.registrationDate = Date.now();
            u.roles.set(Role.Learner);
            u.insert();
            greetUser(u);
            return ServiceHelper.successResponse(authenticate(user.email, user.password));
        }
    }
}
